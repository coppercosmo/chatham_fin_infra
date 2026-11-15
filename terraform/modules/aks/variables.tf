variable "name" { type = string }
variable "control_plane_identity_name" { type = string }
variable "resource_group_name" { type = string }
variable "node_resource_group_name" { type = string }
variable "location" { type = string }
variable "tenant_id" { type = string }
variable "tags" { type = map(string) }

variable "kubernetes_version" {
  type        = string
  default     = null
  description = "null = AKS default. Pin in client config when a client needs to hold a version."
}

variable "subnet_id" {
  type        = string
  description = "snet-aks. Nodes take IPs here; pods use the overlay CIDR, so a /24 is plenty."
}

variable "egress_via_hub_firewall" {
  type        = bool
  default     = false
  description = "Landing-zone mode: the subnet routes 0.0.0.0/0 to the hub firewall, so the cluster uses userDefinedRouting. A plain bool so count is known at plan time."
}

variable "route_table_id" {
  type        = string
  default     = null
  description = "The hub-firewall route table on the node subnet (required when egress_via_hub_firewall)."
}

variable "private_dns_zone_id" {
  type        = string
  default     = "System"
  description = "API server private DNS zone. 'System' = AKS-managed (standalone). Landing zone: P&T's privatelink.<region>.azmk8s.io zone ID."
}

variable "zones" {
  type    = list(string)
  default = ["1", "2", "3"]
}

variable "system_pool" {
  type = object({
    vm_size   = optional(string, "Standard_D4ds_v5")
    min_count = optional(number, 3)
    max_count = optional(number, 5)
  })
  default = {}
}

variable "user_pool" {
  type = object({
    vm_size   = optional(string, "Standard_D8ds_v5")
    min_count = optional(number, 2)
    max_count = optional(number, 10)
  })
  default = {}
}

variable "gpu_pool" {
  type = object({
    vm_size   = optional(string, "Standard_NC24ads_A100_v4")
    min_count = optional(number, 0)
    max_count = optional(number, 2)
  })
  default     = null
  description = "Optional GPU pool for self-hosted models. Tainted so only GPU workloads land there."
}

variable "admin_group_object_ids" {
  type        = list(string)
  default     = []
  description = "P&T-owned Entra group(s) for cluster admin (PIM-eligible). Local accounts are disabled."
}

variable "reader_group_object_id" {
  type    = string
  default = null
}

variable "log_analytics_workspace_id" { type = string }

variable "acr_id" {
  type    = string
  default = null
}

variable "workload_identities" {
  description = "Managed identities pods may use: key => { identity_id (UAMI resource ID), namespace, service_account }."
  type = map(object({
    identity_id     = string
    namespace       = string
    service_account = string
  }))
  default = {}
}

variable "key_vault_id" {
  type        = string
  description = "Client Key Vault. The app routing add-on reads the ingress TLS certificate from it."
}
