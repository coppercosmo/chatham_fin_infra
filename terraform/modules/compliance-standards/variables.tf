variable "assignment_management_group_id" {
  description = "Management group the standards are assigned to: the AI Advisory MG, so the platform subscription and every client, cell and pool subscription below it inherit them."
  type        = string
}

variable "definition_management_group_id" {
  description = "Management group that holds custom standard initiatives (usually P&T's intermediate root). Only needed when custom_standards is not empty."
  type        = string
  default     = null
}

variable "location" {
  description = "Region for each assignment's managed identity (required by Azure when a standard contains DeployIfNotExists rules)."
  type        = string
  default     = "eastus2"
}

variable "standards" {
  description = <<-EOT
    Built-in standards (keys of the catalog in catalog.tf) assigned at the AI Advisory MG. The default is the
    set bank and insurer clients ask a vendor for. MCSB is left out on purpose: P&T assigns it at their
    intermediate root (ALZ does), and the AI Advisory MG inherits it.
  EOT
  type        = list(string)
  default     = ["soc2", "iso27001-2022", "nist80053r5"]

  validation {
    condition     = alltrue([for s in var.standards : contains(keys(local.catalog), s)])
    error_message = "Unknown standard. Use a key from catalog.tf (for example soc2, iso27001-2022, nist80053r5, dora, nist-csf2)."
  }
  validation {
    condition     = length(distinct(var.standards)) == length(var.standards)
    error_message = "List each standard once."
  }
  validation {
    condition     = !contains(var.standards, "ffiec-cat")
    error_message = "The FFIEC retired the Cybersecurity Assessment Tool on 2025-08-31 and points banks to NIST CSF 2.0. Use nist-csf2 for the whole estate; ffiec-cat is only allowed in scoped_standards for a client that still asks for it."
  }
}

variable "scoped_standards" {
  description = <<-EOT
    Extra standards for one client, where its contract or region needs them (for example DORA for an EU bank).
    scope_id is the client's subscription (Tier 1), or its resource group in a cell (Tier 2). A Tier 3 pool is
    one subscription shared by every tenant, so a standard there applies to the whole pool.
  EOT
  type = map(object({
    scope_id  = string       # /subscriptions/<id> or /subscriptions/<id>/resourceGroups/<name>
    standards = list(string) # catalog keys
  }))
  default = {}

  validation {
    condition     = alltrue([for s in var.scoped_standards : can(regex("^/subscriptions/[0-9a-fA-F-]{36}(/resourceGroups/[^/]+)?$", s.scope_id))])
    error_message = "scope_id must be a subscription ID (/subscriptions/<guid>) or a resource group ID (/subscriptions/<guid>/resourceGroups/<name>)."
  }
  validation {
    condition     = alltrue(flatten([for s in var.scoped_standards : [for std in s.standards : contains(keys(local.catalog), std)]]))
    error_message = "Unknown standard in scoped_standards. Use a key from catalog.tf."
  }
  validation {
    condition     = alltrue(flatten([for s in var.scoped_standards : [for std in s.standards : !contains(var.standards, std)]]))
    error_message = "That standard is already assigned at the management group, so every scope below it inherits it."
  }
}

variable "custom_standards_path" {
  description = "Folder of custom standard JSON files. Defaults to the repo's policy/standards folder."
  type        = string
  default     = null
}

variable "custom_standards" {
  description = "Custom standards to build and assign at the AI Advisory MG, by file name in policy/standards without .json (for example nydfs-part-500)."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for c in var.custom_standards : can(regex("^[a-z0-9-]{1,20}$", c))])
    error_message = "Custom standard names are lowercase letters, digits and hyphens, at most 20 characters (the assignment name is std-<name>, 24 characters max)."
  }
}

variable "exemptions" {
  description = <<-EOT
    Accepted gaps against a standard assigned at the MG, for one subscription. Same rules as the guardrails
    (ADR 0002): each one expires and cites the ADR that records why. reference_ids are the rule names inside
    the built-in initiative (for most standards, the policy definition GUID).
  EOT
  type = map(object({
    standard        = string       # a key in var.standards
    subscription_id = string       # /subscriptions/<id>
    reference_ids   = list(string) # rules inside that standard's initiative
    category        = string       # Waiver (accepted risk) or Mitigated (handled another way)
    expires_on      = string       # RFC 3339, e.g. 2027-03-31T00:00:00Z
    reason          = string       # must include "ADR nnnn"
  }))
  default = {}

  validation {
    condition     = alltrue([for e in var.exemptions : contains(var.standards, e.standard)])
    error_message = "An exemption must name a standard assigned at the management group (a key in var.standards)."
  }
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
    error_message = "Every exemption reason must reference the ADR that records it, e.g. \"ADR 0016\"."
  }
}
