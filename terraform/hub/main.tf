# Reference hub (ADR 0013). In Chatham's estate P&T owns and runs the real hub; this root exists so
# the hub-connectivity module can be planned and demoed end to end, and so P&T can see exactly which
# of their existing pieces it plugs into (GatewaySubnet, its route table, the firewall policy).
#
#   10.0.0.0/26    AzureFirewallSubnet   firewall 10.0.0.4
#   10.0.0.64/26   GatewaySubnet         ExpressRoute + VPN gateways (/26: coexistence and up to 16 circuits)
#   10.0.1.0/28    snet-dns-inbound      DNS Private Resolver inbound endpoint 10.0.1.4
#   10.0.1.16/28   snet-dns-outbound     reserved for the resolver's outbound endpoint
#   10.0.2.0/23    reserved              Bastion, P&T shared services

locals {
  tags = merge(var.tags, { workload = "connectivity-hub", owner = "platform-engineering", managed_by = "terraform" })

  routed = { for k, c in var.clients : k => c if contains(["vpn", "expressroute"], try(c.type, "none")) }
  vpn    = { for k, c in local.routed : k => c if c.type == "vpn" }
  er     = { for k, c in local.routed : k => c if c.type == "expressroute" }
}

resource "azurerm_resource_group" "hub" {
  name     = "rg-connectivity-${var.name}"
  location = var.location
  tags     = local.tags
}

resource "azurerm_virtual_network" "hub" {
  name                = "vnet-${var.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name
  address_space       = [var.address_space]
  tags                = local.tags
}

resource "azurerm_subnet" "firewall" {
  name                 = "AzureFirewallSubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.address_space, 4, 0)]
}

resource "azurerm_subnet" "gateway" {
  name                 = "GatewaySubnet"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.address_space, 4, 1)]
}

resource "azurerm_subnet" "dns_inbound" {
  #checkov:skip=CKV2_AZURE_31:Delegated to Microsoft.Network/dnsResolvers; it holds only the resolver's inbound endpoint. Who may query it is decided by routing and the firewall.
  name                 = "snet-dns-inbound"
  resource_group_name  = azurerm_resource_group.hub.name
  virtual_network_name = azurerm_virtual_network.hub.name
  address_prefixes     = [cidrsubnet(var.address_space, 6, 16)]

  delegation {
    name = "dns-resolver"
    service_delegation {
      name    = "Microsoft.Network/dnsResolvers"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
    }
  }
}

# GatewaySubnet keeps gateway route propagation ON (turning it off there isn't supported). The
# module adds one route per client spoke pointing at the firewall.
resource "azurerm_route_table" "gateway" {
  name                          = "rt-${var.name}-gateway"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.hub.name
  bgp_route_propagation_enabled = true
  tags                          = local.tags

  lifecycle {
    ignore_changes = [route] # routes are separate azurerm_route resources, one per client
  }
}

resource "azurerm_subnet_route_table_association" "gateway" {
  subnet_id      = azurerm_subnet.gateway.id
  route_table_id = azurerm_route_table.gateway.id
}

# ---------------------------------------------------------------- firewall (default deny)
resource "azurerm_firewall_policy" "hub" {
  name                     = "afwp-${var.name}"
  location                 = var.location
  resource_group_name      = azurerm_resource_group.hub.name
  sku                      = var.firewall_sku
  threat_intelligence_mode = "Deny"
  tags                     = local.tags

  dynamic "intrusion_detection" {
    for_each = var.firewall_sku == "Premium" ? [1] : []
    content {
      mode = "Deny"
    }
  }
}

resource "azurerm_public_ip" "firewall" {
  name                = "pip-afw-${var.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = ["1", "2", "3"]
  tags                = local.tags
}

resource "azurerm_firewall" "hub" {
  #checkov:skip=CKV_AZURE_216:Policy-managed firewall. Threat intelligence is Deny on the attached azurerm_firewall_policy.hub, which governs it.
  name                = "afw-${var.name}"
  location            = var.location
  resource_group_name = azurerm_resource_group.hub.name
  sku_name            = "AZFW_VNet"
  sku_tier            = var.firewall_sku
  firewall_policy_id  = azurerm_firewall_policy.hub.id
  zones               = ["1", "2", "3"]
  tags                = local.tags

  ip_configuration {
    name                 = "default"
    subnet_id            = azurerm_subnet.firewall.id
    public_ip_address_id = azurerm_public_ip.firewall.id
  }
}

# ---------------------------------------------------------------- per-client secrets (never in tfvars)
data "azurerm_key_vault_secret" "vpn_psk" {
  for_each     = local.vpn
  name         = "vpn-psk-${each.key}"
  key_vault_id = var.secrets_key_vault_id
}

data "azurerm_key_vault_secret" "er_auth" {
  for_each     = local.er
  name         = "er-auth-${each.key}"
  key_vault_id = var.secrets_key_vault_id
}

# ---------------------------------------------------------------- the module
module "connectivity" {
  source              = "../modules/hub-connectivity"
  name                = var.name
  resource_group_name = azurerm_resource_group.hub.name
  location            = var.location
  tags                = local.tags

  hub_vnet_id         = azurerm_virtual_network.hub.id
  hub_address_space   = [var.address_space]
  gateway_subnet_id   = azurerm_subnet.gateway.id
  gateway_route_table = { name = azurerm_route_table.gateway.name, resource_group_name = azurerm_resource_group.hub.name }
  firewall_private_ip = azurerm_firewall.hub.ip_configuration[0].private_ip_address
  firewall_policy_id  = azurerm_firewall_policy.hub.id

  expressroute_gateway           = var.expressroute_gateway
  vpn_gateway                    = var.vpn_gateway
  create_dns_resolver            = true
  dns_resolver_inbound_subnet_id = azurerm_subnet.dns_inbound.id
  dns_resolver_inbound_ip        = cidrhost(azurerm_subnet.dns_inbound.address_prefixes[0], 4)

  clients                         = var.clients
  vpn_shared_keys                 = { for k, s in data.azurerm_key_vault_secret.vpn_psk : k => s.value }
  expressroute_authorization_keys = { for k, s in data.azurerm_key_vault_secret.er_auth : k => s.value }

  depends_on = [azurerm_subnet_route_table_association.gateway]
}
