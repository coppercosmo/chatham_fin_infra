# Spoke VNet for one client. Address plan for the /22 handed out by P&T IPAM:
#
#   x.x.0.0/24   snet-apps (Container Apps, delegated) or snet-aks (AKS nodes, CNI Overlay)
#   x.x.1.0/26   snet-pe   private endpoints
#   x.x.1.64/26  snet-apim API Management AI gateway, internal VNet mode (ADR 0012)
#   x.x.1.128/27 snet-agw-pl  App Gateway Private Link IPs, client_connectivity = privatelink (ADR 0013)
#   x.x.2.0/24   snet-agw  Application Gateway WAF_v2 (dedicated; App Gateway needs its own subnet)
#   x.x.3.0/24   reserved  (second node pool subnet, AGC, growth)

locals {
  workload_prefix = cidrsubnet(var.address_space, 2, 0)
  pe_prefix       = cidrsubnet(var.address_space, 4, 4)
  agw_prefix      = cidrsubnet(var.address_space, 2, 2)
  apim_prefix     = cidrsubnet(var.address_space, 4, 5)
  agw_pl_prefix   = cidrsubnet(var.address_space, 5, 12)
  is_aca          = var.compute_platform == "container_apps"

  # Who may open 443 on App Gateway. With Private Link, connections arrive from the Private Link
  # subnet's addresses, so that subnet is added to whatever the stamp passed in (ADR 0013).
  agw_allowed_sources = concat(
    var.ingress_allowed_source_prefixes,
    var.enable_private_link_subnet ? [local.agw_pl_prefix] : [],
  )

  # Landing zone + client network routed through the hub (VPN or ExpressRoute): replies from
  # App Gateway to the client's network must go back through the hub firewall, the same way the
  # requests came in. Otherwise the firewall only sees half of each connection and drops it.
  route_client_via_firewall = var.hub != null && length(var.client_network_prefixes) > 0

  # Sources allowed to reach private endpoints: the workload subnet, plus App Gateway (it reads
  # its TLS certificate from Key Vault over the vault's private endpoint).
  # And the AI gateway, which calls Azure OpenAI and Content Safety over their private endpoints.
  pe_allowed_sources = concat(
    [local.workload_prefix],
    var.enable_ingress_subnet ? [local.agw_prefix] : [],
    var.enable_apim_subnet ? [local.apim_prefix] : [],
  )
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

# App Gateway Private Link (ADR 0013). Must be its own subnet, separate from snet-agw, with
# Private Link Service network policies off. Each IP here carries up to 64k concurrent connections.
resource "azurerm_subnet" "agw_pl" {
  #checkov:skip=CKV2_AZURE_31:Holds only App Gateway Private Link NAT addresses (no NICs or workloads). Access is enforced on snet-agw's NSG, which only admits this subnet, and by approving each private endpoint connection.
  count                                         = var.enable_private_link_subnet ? 1 : 0
  name                                          = "snet-agw-pl"
  resource_group_name                           = var.resource_group_name
  virtual_network_name                          = azurerm_virtual_network.this.name
  address_prefixes                              = [local.agw_pl_prefix]
  private_link_service_network_policies_enabled = false
}

resource "azurerm_subnet" "apim" {
  count                = var.enable_apim_subnet ? 1 : 0
  name                 = "snet-apim"
  resource_group_name  = var.resource_group_name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [local.apim_prefix]
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
    source_address_prefixes    = local.agw_allowed_sources
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

# API Management internal VNet mode: management endpoint (ApiManagement:3443), the Azure load
# balancer probe (6390), and HTTPS from inside the VNet only.
resource "azurerm_network_security_group" "apim" {
  count               = var.enable_apim_subnet ? 1 : 0
  name                = var.nsg_apim_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  security_rule {
    name                       = "allow-apim-management"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "3443"
    source_address_prefix      = "ApiManagement"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "allow-azure-load-balancer"
    priority                   = 110
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "6390"
    source_address_prefix      = "AzureLoadBalancer"
    destination_address_prefix = "VirtualNetwork"
  }

  security_rule {
    name                       = "allow-https-from-workload"
    priority                   = 200
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = local.workload_prefix
    destination_address_prefix = local.apim_prefix
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

resource "azurerm_subnet_network_security_group_association" "apim" {
  count                     = var.enable_apim_subnet ? 1 : 0
  subnet_id                 = azurerm_subnet.apim[0].id
  network_security_group_id = azurerm_network_security_group.apim[0].id
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
  # Gateway transit: the hub's ExpressRoute/VPN gateway announces this spoke's range to the
  # client's network. Only turned on once P&T's side of the peering allows it (ADR 0013).
  use_remote_gateways = var.use_remote_gateways
}

# ---- Client network over the hub (ADR 0013): App Gateway's route table.
# Gateway route propagation is OFF, so this subnet doesn't learn every client's network from the
# shared hub gateway. The only routes it gets are its own client's ranges, pointed at the firewall.
# Disabling propagation on the App Gateway v2 subnet is a supported configuration; 0.0.0.0/0 is
# deliberately not touched (v2 needs a direct path for its management traffic).
resource "azurerm_route_table" "agw" {
  count                         = local.route_client_via_firewall && var.enable_ingress_subnet ? 1 : 0
  name                          = "${var.route_table_name}-agw"
  location                      = var.location
  resource_group_name           = var.resource_group_name
  bgp_route_propagation_enabled = false
  tags                          = var.tags

  dynamic "route" {
    for_each = toset(var.client_network_prefixes)
    content {
      name                   = "client-${replace(replace(route.value, ".", "-"), "/", "_")}-via-firewall"
      address_prefix         = route.value
      next_hop_type          = "VirtualAppliance"
      next_hop_in_ip_address = var.hub.firewall_private_ip
    }
  }
}

resource "azurerm_subnet_route_table_association" "agw" {
  count          = length(azurerm_route_table.agw)
  subnet_id      = azurerm_subnet.agw[0].id
  route_table_id = azurerm_route_table.agw[0].id
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
