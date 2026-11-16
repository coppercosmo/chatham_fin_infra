variable "definition_management_group_id" {
  description = "Management group that holds the custom definitions and the initiative, usually P&T's intermediate root (e.g. the Chatham MG), so any child MG can assign them."
  type        = string
}

variable "assignment_management_group_id" {
  description = "Management group the initiative is assigned to: the AI Advisory MG, so it covers the platform subscription and every client subscription below it."
  type        = string
}

variable "location" {
  description = "Region for the assignment's managed identity (needed by the DeployIfNotExists and Modify effects)."
  type        = string
  default     = "eastus2"
}

variable "definitions_path" {
  description = "Folder of policy definition JSON files. Defaults to the repo's policy/ folder."
  type        = string
  default     = null
}

variable "enforce" {
  description = "false = DoNotEnforce: every rule is evaluated and reported, nothing is denied or deployed. Roll out with false, read the compliance report, fix or exempt, then set true."
  type        = bool
  default     = false
}

variable "required_tags" {
  description = "Tags every resource group must have. Resources inherit the value from their resource group."
  type        = list(string)
  default     = ["client", "cost_center", "data_classification", "owner"]
}

variable "allowed_locations" {
  description = "Regions resources may be created in (built-in 'Allowed locations'). Keep both regions of a DR pair in the list."
  type        = list(string)
  default     = ["eastus2", "centralus"]
}

variable "allowed_openai_deployment_skus" {
  description = "Model deployment SKUs allowed for data residency. GlobalStandard is deliberately absent (ADR 0006)."
  type        = list(string)
  default     = ["DataZoneStandard", "Standard", "ProvisionedManaged", "DataZoneProvisionedManaged"]
}

variable "private_dns_zones" {
  description = <<-EOT
    One DeployIfNotExists rule per private endpoint type: when an endpoint for resource_type/group_id
    has no DNS zone group, register it in zone_ids (P&T's central privatelink zones in the hub).
    Empty map = leave private DNS to an existing P&T assignment.
  EOT
  type = map(object({
    resource_type = string       # e.g. Microsoft.KeyVault/vaults
    group_id      = string       # e.g. vault
    zone_ids      = list(string) # e.g. [".../privateDnsZones/privatelink.vaultcore.azure.net"]
  }))
  default = {}
}

variable "dns_zone_scope_ids" {
  description = "Scopes holding the central private DNS zones (usually a resource group in P&T's connectivity subscription). The assignment's identity needs Network Contributor there to write records."
  type        = list(string)
  default     = []
}

variable "exemptions" {
  description = <<-EOT
    Time-boxed exemptions for a client subscription (ADR 0002: exemptions are recorded, never silent).
    Each one must expire and must name the ADR that records why.
  EOT
  type = map(object({
    subscription_id = string       # /subscriptions/<id>
    reference_ids   = list(string) # which rules in the initiative, e.g. ["deny-paas-public-network"]
    category        = string       # Waiver (accepted risk) or Mitigated (handled another way)
    expires_on      = string       # RFC 3339, e.g. 2027-03-31T00:00:00Z
    reason          = string       # must include "ADR nnnn"
  }))
  default = {}

  validation {
    condition     = alltrue([for e in var.exemptions : contains(["Waiver", "Mitigated"], e.category)])
    error_message = "Exemption category must be Waiver or Mitigated."
  }
  validation {
    condition     = alltrue([for e in var.exemptions : can(regex("^\\d{4}-\\d{2}-\\d{2}T", e.expires_on))])
    error_message = "Every exemption needs an expiry date (RFC 3339). Permanent exemptions are not allowed."
  }
  validation {
    condition     = alltrue([for e in var.exemptions : can(regex("ADR \\d{4}", e.reason))])
    error_message = "Every exemption reason must reference the ADR that records it, e.g. \"ADR 0014\"."
  }
}
