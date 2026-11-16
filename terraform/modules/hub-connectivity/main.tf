# Hub connectivity for AI Advisory clients (ADR 0013). Owned and applied by Platform Engineering
# (P&T) in the connectivity subscription; proposed by AI Advisory the same way as policy/.
#
#   client network --ExpressRoute / IPsec VPN--> [hub gateway] --GatewaySubnet route--> [hub firewall]
#        --allow: this client's ranges -> this client's App Gateway IP, TCP 443 only--> [client spoke]
#
# Everything per client is keyed by client code, so adding or removing one client never touches
# another client's connection, routes, firewall rules or DNS zone.

locals {
  vpn_clients    = { for k, c in var.clients : k => c if c.type == "vpn" }
  er_clients     = { for k, c in var.clients : k => c if c.type == "expressroute" }
  routed_clients = merge(local.vpn_clients, local.er_clients)

  hub_vnet_rg   = split("/", var.hub_vnet_id)[4]
  hub_vnet_name = split("/", var.hub_vnet_id)[8]

  er_gateway_id  = var.expressroute_gateway != null ? azurerm_virtual_network_gateway.er[0].id : var.existing_expressroute_gateway_id
  vpn_gateway_id = var.vpn_gateway != null ? azurerm_virtual_network_gateway.vpn[0].id : var.existing_vpn_gateway_id

  dns_forwarder_ip = var.create_dns_resolver ? azurerm_private_dns_resolver_inbound_endpoint.this[0].ip_configurations[0].private_ip_address : var.existing_dns_forwarder_ip

  # Max ExpressRoute circuits per gateway SKU (Microsoft limits).
  er_circuit_limit = { ErGw1AZ = 4, ErGw2AZ = 8, ErGw3AZ = 16 }

  nat_rules = merge([
    for k, c in local.vpn_clients : {
      for i, m in try(c.vpn.nat, []) : "${k}-${i}" => merge(m, { client = k })
    }
  ]...)

  priorities = [for c in values(local.routed_clients) : c.firewall_priority if c.firewall_priority != null]
}

# ---------------------------------------------------------------- rules that span clients
# A shared hub is only safe if no two clients look alike to its routers. Checked at plan time.
module "overlap" {
  source = "../cidr-overlap"
  prefixes = merge(
    { "hub" = var.hub_address_space },
    { for k, c in var.clients : "${k} spoke" => [c.spoke_prefix] },
    { for k, c in local.routed_clients : "${k} network" => c.on_prem_prefixes },
  )
}

resource "terraform_data" "checks" {
  input = sort(keys(local.routed_clients))

  lifecycle {
    precondition {
      condition     = length(module.overlap.overlaps) == 0
      error_message = "Address clash: ${join("; ", module.overlap.overlaps)}. Give the client a NAT range (VPN), ask them to advertise a unique range (ExpressRoute), or use Private Link."
    }
    precondition {
      condition = alltrue([for c in values(local.routed_clients) :
        c.firewall_priority != null && c.ingress_ip != null && c.host_name != null && length(c.on_prem_prefixes) > 0
      ])
      error_message = "Each vpn/expressroute client needs firewall_priority, ingress_ip, host_name and on_prem_prefixes."
    }
    precondition {
      condition     = length(local.priorities) == length(distinct(local.priorities))
      error_message = "firewall_priority must be unique per client."
    }
    precondition {
      condition     = length(local.vpn_clients) == 0 || local.vpn_gateway_id != null
      error_message = "VPN clients need vpn_gateway (or existing_vpn_gateway_id)."
    }
    precondition {
      condition     = length(local.er_clients) == 0 || local.er_gateway_id != null
      error_message = "ExpressRoute clients need expressroute_gateway (or existing_expressroute_gateway_id)."
    }
    precondition {
      condition     = alltrue([for k in keys(local.vpn_clients) : contains(nonsensitive(keys(var.vpn_shared_keys)), k)])
      error_message = "Every VPN client needs a pre-shared key in vpn_shared_keys."
    }
    precondition {
      condition     = var.expressroute_gateway == null || length(local.er_clients) <= lookup(local.er_circuit_limit, try(var.expressroute_gateway.sku, ""), 4)
      error_message = "More ExpressRoute clients than the gateway SKU allows circuits; move to a larger ErGw SKU."
    }
    precondition {
      condition     = !var.create_dns_resolver || var.dns_resolver_inbound_subnet_id != null
      error_message = "create_dns_resolver needs dns_resolver_inbound_subnet_id."
    }
    precondition {
      condition     = length(local.nat_rules) == 0 || var.vpn_gateway == null || !can(regex("^VpnGw1", try(var.vpn_gateway.sku, "")))
      error_message = "NAT needs VpnGw2AZ or larger."
    }
  }
}

# ---------------------------------------------------------------- ExpressRoute gateway
resource "azurerm_virtual_network_gateway" "er" {
  count               = var.expressroute_gateway != null ? 1 : 0
  name                = "ergw-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  type                = "ExpressRoute"
  sku                 = var.expressroute_gateway.sku
  tags                = var.tags

  # The circuit is a private router-to-router link, so traffic between networks that share it is
  # off: a client's own Azure VNets on the same circuit can't hairpin into this hub, and nothing
  # reaches us from Virtual WAN through it (ADR 0013).
  remote_vnet_traffic_enabled = false
  virtual_wan_traffic_enabled = false

  ip_configuration {
    name      = "default"
    subnet_id = var.gateway_subnet_id
    # No public IP argument: Azure auto-assigns and manages one for ExpressRoute gateways.
  }
}

resource "azurerm_virtual_network_gateway_connection" "er" {
  for_each                   = local.er_clients
  name                       = "con-${var.name}-${each.key}-er"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  type                       = "ExpressRoute"
  virtual_network_gateway_id = local.er_gateway_id
  express_route_circuit_id   = each.value.expressroute.circuit_id
  authorization_key          = lookup(var.expressroute_authorization_keys, each.key, null)
  routing_weight             = each.value.expressroute.routing_weight
  tags                       = merge(var.tags, { client = each.key })

  depends_on = [terraform_data.checks]
}

# ---------------------------------------------------------------- site-to-site VPN gateway
resource "azurerm_public_ip" "vpn" {
  count               = var.vpn_gateway == null ? 0 : (var.vpn_gateway.active_active ? 2 : 1)
  name                = "pip-vpngw-${var.name}-${count.index + 1}"
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones
  tags                = var.tags
}

resource "azurerm_virtual_network_gateway" "vpn" {
  count               = var.vpn_gateway != null ? 1 : 0
  name                = "vpngw-${var.name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  type                = "Vpn"
  vpn_type            = "RouteBased"
  sku                 = var.vpn_gateway.sku
  generation          = "Generation2"
  active_active       = var.vpn_gateway.active_active
  # BGP stays off for client tunnels. With BGP the gateway passes routes learned from one peer to
  # every other peer, which would tell client A how to reach client B's network. Client ranges are
  # static on each client's local network gateway instead (ADR 0013).
  bgp_enabled = false
  tags        = var.tags

  dynamic "ip_configuration" {
    for_each = azurerm_public_ip.vpn
    content {
      name                 = "ipconfig${ip_configuration.key + 1}"
      subnet_id            = var.gateway_subnet_id
      public_ip_address_id = ip_configuration.value.id
    }
  }
}

# The client's VPN device and the ranges behind it (post-NAT, i.e. as seen inside Azure).
resource "azurerm_local_network_gateway" "client" {
  for_each            = local.vpn_clients
  name                = "lgw-${var.name}-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  gateway_address     = each.value.vpn.device_public_ip
  address_space       = each.value.on_prem_prefixes
  tags                = merge(var.tags, { client = each.key })
}

# Static 1:1 NAT for clients whose real range collides with another client or a spoke: the client
# keeps its own addresses at home and appears in Azure as a unique range from P&T's IPAM.
resource "azurerm_virtual_network_gateway_nat_rule" "client" {
  for_each                   = local.nat_rules
  name                       = "nat-${each.key}"
  resource_group_name        = var.resource_group_name
  virtual_network_gateway_id = local.vpn_gateway_id
  mode                       = "IngressSnat"
  type                       = "Static"

  internal_mapping {
    address_space = each.value.client_prefix # what the client really uses
  }
  external_mapping {
    address_space = each.value.azure_prefix # what Azure sees
  }
}

resource "azurerm_virtual_network_gateway_connection" "vpn" {
  for_each                   = local.vpn_clients
  name                       = "con-${var.name}-${each.key}-s2s"
  location                   = var.location
  resource_group_name        = var.resource_group_name
  type                       = "IPsec"
  connection_protocol        = "IKEv2"
  virtual_network_gateway_id = local.vpn_gateway_id
  local_network_gateway_id   = azurerm_local_network_gateway.client[each.key].id
  shared_key                 = var.vpn_shared_keys[each.key]
  bgp_enabled                = false
  dpd_timeout_seconds        = 45
  ingress_nat_rule_ids       = [for k, r in azurerm_virtual_network_gateway_nat_rule.client : r.id if local.nat_rules[k].client == each.key]
  tags                       = merge(var.tags, { client = each.key })

  ipsec_policy {
    ike_encryption   = var.ipsec_policy.ike_encryption
    ike_integrity    = var.ipsec_policy.ike_integrity
    dh_group         = var.ipsec_policy.dh_group
    ipsec_encryption = var.ipsec_policy.ipsec_encryption
    ipsec_integrity  = var.ipsec_policy.ipsec_integrity
    pfs_group        = var.ipsec_policy.pfs_group
    sa_lifetime      = var.ipsec_policy.sa_lifetime
  }

  depends_on = [terraform_data.checks]
}

# ---------------------------------------------------------------- routing: through the firewall, both ways
# Inbound: anything the gateway receives for a client's spoke goes to the firewall first. (The
# return leg is the App Gateway subnet's route table in the client stamp.)
resource "azurerm_route" "gateway_to_spoke" {
  for_each               = local.routed_clients
  name                   = "client-${each.key}-spoke-via-firewall"
  resource_group_name    = var.gateway_route_table.resource_group_name
  route_table_name       = var.gateway_route_table.name
  address_prefix         = each.value.spoke_prefix
  next_hop_type          = "VirtualAppliance"
  next_hop_in_ip_address = var.firewall_private_ip
}

# ---------------------------------------------------------------- firewall: one client, one door
# The only thing a client's network may reach is that client's App Gateway, on 443. Client A's
# ranges never appear in a rule that leads to client B, and the policy's default is deny.
resource "azurerm_firewall_policy_rule_collection_group" "client" {
  for_each           = local.routed_clients
  name               = "rcg-aiadv-${each.key}"
  firewall_policy_id = var.firewall_policy_id
  priority           = each.value.firewall_priority

  network_rule_collection {
    name     = "allow-${each.key}-network-to-ingress"
    priority = 100
    action   = "Allow"

    rule {
      name                  = "client-network-to-app-gateway-https"
      description           = "${each.key}: client network to its own App Gateway only (ADR 0013)"
      protocols             = ["TCP"]
      source_addresses      = each.value.on_prem_prefixes
      destination_addresses = [each.value.ingress_ip]
      destination_ports     = ["443"]
    }
  }

  depends_on = [terraform_data.checks]
}

# ---------------------------------------------------------------- DNS
# Clients conditionally forward their own host name (e.g. acme.ai.chatham.example.com) to the
# resolver's inbound IP. A zone per client means each client's DNS team forwards one name only.
resource "azurerm_private_dns_resolver" "this" {
  count               = var.create_dns_resolver ? 1 : 0
  name                = "dnspr-${var.name}"
  resource_group_name = var.resource_group_name
  location            = var.location
  virtual_network_id  = var.hub_vnet_id
  tags                = var.tags
}

resource "azurerm_private_dns_resolver_inbound_endpoint" "this" {
  count                   = length(azurerm_private_dns_resolver.this)
  name                    = "in-${var.name}"
  private_dns_resolver_id = azurerm_private_dns_resolver.this[0].id
  location                = var.location
  tags                    = var.tags

  ip_configurations {
    subnet_id                    = var.dns_resolver_inbound_subnet_id
    private_ip_allocation_method = var.dns_resolver_inbound_ip == null ? "Dynamic" : "Static"
    private_ip_address           = var.dns_resolver_inbound_ip
  }
}

resource "azurerm_private_dns_zone" "client" {
  for_each            = var.create_client_dns_zones ? local.routed_clients : {}
  name                = each.value.host_name
  resource_group_name = var.resource_group_name
  tags                = merge(var.tags, { client = each.key })
}

resource "azurerm_private_dns_a_record" "client" {
  for_each            = azurerm_private_dns_zone.client
  name                = "@"
  zone_name           = each.value.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [local.routed_clients[each.key].ingress_ip]
  tags                = merge(var.tags, { client = each.key })
}

resource "azurerm_private_dns_zone_virtual_network_link" "client" {
  for_each              = azurerm_private_dns_zone.client
  name                  = "link-hub"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = each.value.name
  virtual_network_id    = var.hub_vnet_id
  registration_enabled  = false
  tags                  = merge(var.tags, { client = each.key })
}

# ---------------------------------------------------------------- hub side of each spoke peering
# Gateway transit only for clients whose network comes in through a hub gateway. Other spokes
# don't get the gateway's routes (and the gateway doesn't announce them to anyone's network).
resource "azurerm_virtual_network_peering" "to_spoke" {
  for_each                  = var.create_hub_peerings ? var.clients : {}
  name                      = "peer-to-${each.key}"
  resource_group_name       = local.hub_vnet_rg
  virtual_network_name      = local.hub_vnet_name
  remote_virtual_network_id = each.value.spoke_vnet_id
  allow_forwarded_traffic   = true
  allow_gateway_transit     = contains(["vpn", "expressroute"], each.value.type)
}
