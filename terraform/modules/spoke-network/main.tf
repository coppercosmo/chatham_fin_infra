locals {
  # /22 -> apps /24 (first), private endpoints /26 (next /24, first /26)
  apps_prefix = cidrsubnet(var.address_space, 2, 0)
  pe_prefix   = cidrsubnet(var.address_space, 4, 4)
}

resource "azurerm_virtual_network" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  address_space       = [var.address_space]
  dns_servers         = var.hub == null ? [] : var.hub.dns_servers
  tags                = var.tags
}

resource "azurerm_subnet" "apps" {
  name                 = "snet-apps"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.apps_prefix]

  delegation {
    name = "aca"
    service_delegation {
      name    = "Microsoft.App/environments"
      actions = ["Microsoft.Network/virtualNetworks/subnets/join/action"]
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

# ---- NSGs: deny inbound from anywhere except our own VNet; private endpoints only reachable from apps subnet.
resource "azurerm_network_security_group" "apps" {
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
    destination_address_prefix = local.apps_prefix
  }
}

resource "azurerm_network_security_group" "pe" {
  name                = var.nsg_pe_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "allow-https-from-apps"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = local.apps_prefix
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

resource "azurerm_subnet_network_security_group_association" "apps" {
  subnet_id                 = azurerm_subnet.apps.id
  network_security_group_id = azurerm_network_security_group.apps.id
}

resource "azurerm_subnet_network_security_group_association" "pe" {
  subnet_id                 = azurerm_subnet.pe.id
  network_security_group_id = azurerm_network_security_group.pe.id
}

# ---- Landing-zone mode: force egress through the hub firewall and peer to the hub.
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

resource "azurerm_subnet_route_table_association" "apps" {
  count          = var.hub == null ? 0 : 1
  subnet_id      = azurerm_subnet.apps.id
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
