variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }

variable "address_space" {
  type        = string
  description = "Spoke CIDR allocated by P&T IPAM, e.g. 10.100.0.0/22."
}

variable "nsg_apps_name" { type = string }
variable "nsg_pe_name" { type = string }
variable "route_table_name" { type = string }

variable "hub" {
  description = <<-EOT
    Landing-zone connectivity. null = standalone mode (no peering, Azure-provided DNS, no forced egress).
    firewall_private_ip: next hop for 0.0.0.0/0. dns_servers: hub DNS resolver inbound IPs.
    vnet_id: hub VNet for the spoke-side peering (P&T creates the hub-side peering).
  EOT
  type = object({
    vnet_id             = string
    firewall_private_ip = string
    dns_servers         = list(string)
  })
  default = null
}

variable "compute_platform" {
  type        = string
  default     = "container_apps"
  description = "container_apps: workload subnet delegated to Microsoft.App. aks: plain subnet for AKS nodes (Azure CNI Overlay)."
  validation {
    condition     = contains(["container_apps", "aks"], var.compute_platform)
    error_message = "compute_platform must be container_apps or aks."
  }
}

variable "enable_ingress_subnet" {
  type        = bool
  default     = false
  description = "Create the dedicated Application Gateway subnet."
}

variable "enable_apim_subnet" {
  type        = bool
  default     = false
  description = "Create the dedicated API Management (AI gateway) subnet."
}

variable "nsg_apim_name" {
  type    = string
  default = null
}

variable "nsg_agw_name" {
  type    = string
  default = null
}

variable "ingress_allowed_source_prefixes" {
  type        = list(string)
  default     = ["VirtualNetwork"]
  description = <<-EOT
    Who may reach the Application Gateway on 443. Private ingress over the hub: the client's own network
    ranges (never the VirtualNetwork tag, which also matches every other client's network learned by the
    shared hub gateway). Public ingress: client egress CIDRs or the AzureFrontDoor.Backend service tag.
    The Private Link subnet is added automatically when enable_private_link_subnet is true.
  EOT
}

variable "client_network_prefixes" {
  type        = list(string)
  default     = []
  description = "Landing zone only: the client's own network ranges (as seen in Azure, after any NAT) that reach App Gateway through the hub. Routed back via the hub firewall."
}

variable "use_remote_gateways" {
  type        = bool
  default     = false
  description = "Use the hub's ExpressRoute/VPN gateway (gateway transit). Needs a gateway in the hub and P&T's hub-side peering with allow_gateway_transit."
}

variable "enable_private_link_subnet" {
  type        = bool
  default     = false
  description = "Create snet-agw-pl for App Gateway Private Link (client_connectivity = privatelink)."
}
