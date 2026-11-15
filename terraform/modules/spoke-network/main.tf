# Spoke VNet for one client. Address plan for the /22 handed out by P&T IPAM:
#
#   x.x.0.0/24   snet-apps (Container Apps, delegated) or snet-aks (AKS nodes, CNI Overlay)
#   x.x.1.0/26   snet-pe   private endpoints
#   x.x.2.0/24   snet-agw  Application Gateway WAF_v2 (dedicated; App Gateway needs its own subnet)
#   x.x.3.0/24   reserved  (second node pool subnet, AGC, growth)

locals {
  workload_prefix = cidrsubnet(var.address_space, 2, 0)
  pe_prefix       = cidrsubnet(var.address_space, 4, 4)
  agw_prefix      = cidrsubnet(var.address_space, 2, 2)
  is_aca          = var.compute_platform == "container_apps"

  # Sources allowed to reach private endpoints: the workload subnet, plus App Gateway (it reads
  # its TLS certificate from Key Vault over the vault's private endpoint).
  pe_allowed_sources = concat([local.workload_prefix], var.enable_ingress_subnet ? [local.agw_prefix] : [])
}

resource "azurerm_virtual_network" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.address_space]
  dns_servers         = var.hub == null ? [] : var.hub.dns_servers
  tags                = var.tags
}

resource "azurerm_subnet" "workload" {
  name                 = local.is_aca ? "snet-apps" : "snet-aks"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.workload_prefix]

  dynamic "delegation" {
    for_each = local.is_aca ? [1] : []
    content {
      name = "aca"
      service_delegation {
        name    = "Microsoft.App/environments"
        actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
      }
    }
  }
}

resource "azurerm_subnet" "pe" {
  name                              = "snet-pe"
  resource_group_name               = var.resource_group_name
  virtual_network_name              = azurerm_virtual_network.this.name
  address_prefixes                  = [local.pe_prefix]
  private_endpoint_network_policies = "Enabled" # lets NSGs/UDRs apply to private endpoints
}

resource "azurerm_subnet" "agw" {
  count                = var.enable_ingress_subnet ? 1 : 0
  name                 = "snet-agw"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.agw_prefix]
}

# ---- NSGs
resource "azurerm_network_security_group" "workload" {
  name                = var.nsg_apps_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "allow-https-from-vnet"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_ranges    = ["80", "443"]
    source_address_prefix      = "VirtualNetwork"
    destination_address_prefix = local.workload_prefix
  }
}

resource "azurerm_network_security_group" "pe" {
  name                = var.nsg_pe_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "allow-https-from-workload-and-agw"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefixes    = local.pe_allowed_sources
    destination_address_prefix = local.pe_prefix
  }

  security_rule {
    name                       = "deny-all-other-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# App Gateway v2 subnet rules: platform health probes (GatewayManager 65200-65535) and the Azure
# load balancer must be allowed, then 443 only from the sources this client is reachable from.
resource "azurerm_network_security_group" "agw" {
  count               = var.enable_ingress_subnet ? 1 : 0
  name                = var.nsg_agw_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "allow-gateway-manager"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "65200-65535"
    source_address_prefix      = "GatewayManager"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-azure-load-balancer"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "*"
  }

  security_rule {
    name                       = "allow-https-from-approved-sources"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefixes    = var.ingress_allowed_source_prefixes
    destination_address_prefix = local.agw_prefix
  }

  security_rule {
    name                       = "deny-all-other-inbound"
    priority                   = 4000
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

resource "azurerm_subnet_network_security_group_association" "workload" {
  subnet_id                 = azurerm_subnet.workload.id
  network_security_group_id = azurerm_network_security_group.workload.id
}

resource "azurerm_subnet_network_security_group_association" "pe" {
  subnet_id                 = azurerm_subnet.pe.id
  network_security_group_id = azurerm_network_security_group.pe.id
}

resource "azurerm_subnet_network_security_group_association" "agw" {
  count                     = var.enable_ingress_subnet ? 1 : 0
  subnet_id                 = azurerm_subnet.agw[0].id
  network_security_group_id = azurerm_network_security_group.agw[0].id
}

# ---- Landing-zone mode: force workload egress through the hub firewall and peer to the hub.
# The App Gateway subnet is deliberately NOT forced through the firewall: v2 gateways need direct
# return paths for their control plane unless the private-only (network isolation) deployment is used.
resource "azurerm_route_table" "this" {
  count                         = var.hub == null ? 0 : 1
  name                          = var.route_table_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = false
  tags                          = var.tags

  route {
    name                   = "default-to-hub-firewall"
    address_prefix         = "0.0.0.0/0"
    next_hop_type          = "VirtualAppliance"
    next_hop_in_ip_address = var.hub.firewall_private_ip
  }
}

resource "azurerm_subnet_route_table_association" "workload" {
  count          = var.hub == null ? 0 : 1
  subnet_id      = azurerm_subnet.workload.id
  route_table_id = azurerm_route_table.this[0].id
}

resource "azurerm_virtual_network_peering" "to_hub" {
  count                     = var.hub == null ? 0 : 1
  name                      = "peer-to-hub"
  resource_group_name       = var.resource_group_name
  virtual_network_name      = azurerm_virtual_network.this.name
  remote_virtual_network_id = var.hub.vnet_id
  allow_forwarded_traffic   = true
  use_remote_gateways       = false
}

# Renamed when AKS support was added; keeps existing client networks in place (no recreate).
moved {
  from = azurerm_subnet.apps
  to   = azurerm_subnet.workload
}
moved {
  from = azurerm_network_security_group.apps
  to   = azurerm_network_security_group.workload
}
moved {
  from = azurerm_subnet_network_security_group_association.apps
  to   = azurerm_subnet_network_security_group_association.workload
}
moved {
  from = azurerm_subnet_route_table_association.apps
  to   = azurerm_subnet_route_table_association.workload
}
