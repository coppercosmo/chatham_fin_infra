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

variable "nsg_agw_name" {
  type    = string
  default = null
}

variable "ingress_allowed_source_prefixes" {
  type        = list(string)
  default     = ["VirtualNetwork"]
  description = "Who may reach the Application Gateway on 443. Private ingress: VirtualNetwork (hub, ExpressRoute/VPN). Public ingress: client egress CIDRs or the AzureFrontDoor.Backend service tag."
}
