variable "name" {
  type        = string
  description = "Base for resource names, e.g. hub-eus2."
}
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tags" {
  type    = map(string)
  default = {}
}
variable "zones" {
  type    = list(string)
  default = ["1", "2", "3"]
}

# ---------------------------------------------------------------- the hub P&T already runs
variable "hub_vnet_id" { type = string }

variable "hub_address_space" {
  type        = list(string)
  description = "Hub VNet ranges. Client networks must not overlap them."
}

variable "gateway_subnet_id" {
  type        = string
  default     = null
  description = "GatewaySubnet (/27 minimum, /26 recommended when ExpressRoute and VPN share it). Needed when either gateway is created."
}

variable "gateway_route_table" {
  description = "The route table on GatewaySubnet. Per-client routes send traffic for each client's spoke to the firewall."
  type = object({
    name                = string
    resource_group_name = string
  })
}

variable "firewall_private_ip" { type = string }

variable "firewall_policy_id" {
  type        = string
  description = "P&T's Azure Firewall policy. One rule collection group is added per routed client."
}

# ---------------------------------------------------------------- gateways (null = don't create)
variable "expressroute_gateway" {
  description = "ExpressRoute gateway in the hub. null = none (or P&T's existing one: set existing_expressroute_gateway_id)."
  type = object({
    sku = optional(string, "ErGw1AZ")
  })
  default = null

  validation {
    condition     = var.expressroute_gateway == null || contains(["ErGw1AZ", "ErGw2AZ", "ErGw3AZ"], try(var.expressroute_gateway.sku, ""))
    error_message = "Use a zone-redundant ExpressRoute gateway SKU: ErGw1AZ, ErGw2AZ or ErGw3AZ."
  }
}

variable "existing_expressroute_gateway_id" {
  type    = string
  default = null
}

variable "vpn_gateway" {
  description = "Site-to-site VPN gateway in the hub. null = none (or P&T's existing one: set existing_vpn_gateway_id)."
  type = object({
    sku           = optional(string, "VpnGw2AZ") # VpnGw2AZ or larger is needed for NAT
    active_active = optional(bool, true)
  })
  default = null

  validation {
    condition     = var.vpn_gateway == null || can(regex("^VpnGw[1-5]AZ$", try(var.vpn_gateway.sku, "")))
    error_message = "Use a zone-redundant VPN gateway SKU, VpnGw1AZ to VpnGw5AZ."
  }
}

variable "existing_vpn_gateway_id" {
  type    = string
  default = null
}

variable "ipsec_policy" {
  description = "IPsec/IKE parameters for client tunnels. Defaults are a strong IKEv2 profile; agree them with each client's network team."
  type = object({
    ike_encryption   = optional(string, "AES256")
    ike_integrity    = optional(string, "SHA384")
    dh_group         = optional(string, "ECP384")
    ipsec_encryption = optional(string, "GCMAES256")
    ipsec_integrity  = optional(string, "GCMAES256")
    pfs_group        = optional(string, "ECP384")
    sa_lifetime      = optional(number, 27000)
  })
  default = {}
}

# ---------------------------------------------------------------- DNS
variable "create_dns_resolver" {
  type        = bool
  default     = false
  description = "Create an Azure DNS Private Resolver with an inbound endpoint. false = P&T already runs one: set existing_dns_forwarder_ip."
}

variable "dns_resolver_inbound_subnet_id" {
  type        = string
  default     = null
  description = "Subnet for the resolver's inbound endpoint (/28 minimum, delegated to Microsoft.Network/dnsResolvers)."
}

variable "dns_resolver_inbound_ip" {
  type        = string
  default     = null
  description = "Static IP for the inbound endpoint, so client DNS teams can configure it before it exists."
}

variable "existing_dns_forwarder_ip" {
  type    = string
  default = null
}

variable "create_client_dns_zones" {
  type        = bool
  default     = true
  description = "One private DNS zone per routed client (its host name), so each client forwards only its own name to the resolver."
}

# ---------------------------------------------------------------- clients
variable "clients" {
  description = <<-EOT
    Every client spoke in the landing zone, keyed by client code. Built from each client stamp's
    `hub_connectivity_request` output (vpn/expressroute) plus P&T's own fields (firewall_priority).
    Clients with type none or privatelink only get the hub-side peering.
  EOT
  type = map(object({
    type              = string
    spoke_vnet_id     = string
    spoke_prefix      = string
    ingress_ip        = optional(string)
    host_name         = optional(string)
    on_prem_prefixes  = optional(list(string), [])
    firewall_priority = optional(number) # unique per client, assigned by P&T (routed clients only)
    vpn = optional(object({
      device_public_ip = string
      nat = optional(list(object({
        client_prefix = string
        azure_prefix  = string
      })), [])
    }))
    expressroute = optional(object({
      circuit_id     = string
      routing_weight = optional(number, 0)
    }))
  }))
  default = {}

  validation {
    condition     = alltrue([for c in values(var.clients) : contains(["none", "privatelink", "vpn", "expressroute"], c.type)])
    error_message = "Each client's type must be none, privatelink, vpn or expressroute."
  }
}

variable "vpn_shared_keys" {
  type        = map(string)
  default     = {}
  sensitive   = true
  description = "Client code => IPsec pre-shared key. Read from P&T's Key Vault by the caller, never committed."
}

variable "expressroute_authorization_keys" {
  type        = map(string)
  default     = {}
  sensitive   = true
  description = "Client code => authorization key the client issued on their circuit for our gateway."
}

variable "create_hub_peerings" {
  type        = bool
  default     = true
  description = "Create the hub side of each spoke peering. Set false if P&T's subscription vending already does."
}
