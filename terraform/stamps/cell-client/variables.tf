# Tier 2 per-client root (ADR 0014): everything that stores this client's data, in its own resource group
# inside a shared cell subscription. Applied by the client's OWN deployment identity, whose rights stop at
# this resource group. Hand output.cell_registration to the cell (terraform/cells/<cell>/terraform.tfvars).

variable "client" {
  type = string
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,11}$", var.client))
    error_message = "client must be 2-12 lowercase letters/digits, starting with a letter."
  }
}

variable "environment" {
  type    = string
  default = "prd"
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "subscription_id" {
  type        = string
  description = "The CELL's subscription. The client has a resource group in it, not a subscription of its own."
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "data_classification" {
  type    = string
  default = "confidential"
  validation {
    condition     = contains(["internal", "confidential"], var.data_classification)
    error_message = "Tier 2 takes internal or confidential data. highly-confidential (or a contract that asks for a dedicated subscription) goes to Tier 1."
  }
}

variable "cost_center" { type = string }
variable "owner_email" { type = string }

variable "cell" {
  description = "From the cell's output cell_inputs_for_clients, plus the cell deployment identity's principal ID."
  type = object({
    name                  = string
    pe_subnet_id          = string
    search_service_id     = string
    private_dns_zone_ids  = optional(map(string), {}) # standalone cells only; landing-zone DNS is P&T's policy
    deployer_principal_id = optional(string)          # needs Managed Identity Operator to attach our identities
  })
}

variable "model_deployments" {
  type = map(object({
    model_name    = string
    model_version = string
    sku           = optional(string, "DataZoneStandard")
    capacity      = optional(number, 10)
  }))
  default = {
    chat       = { model_name = "gpt-4o", model_version = "2024-11-20", capacity = 20 }
    embeddings = { model_name = "text-embedding-3-large", model_version = "1", capacity = 20 }
  }
  validation {
    condition     = alltrue([for d in values(var.model_deployments) : !startswith(d.sku, "Provisioned") && !startswith(d.sku, "DataZoneProvisioned") && !startswith(d.sku, "GlobalProvisioned")])
    error_message = "PTU capacity of a client's own is a Tier 1 feature (ADR 0014): a cell's quota and capacity planning is shared."
  }
}

variable "reader_group_object_id" {
  type    = string
  default = null
}

variable "acr" {
  type = object({
    id           = string
    login_server = string
  })
  default = null
}

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "monthly_budget_usd" {
  type    = number
  default = 500
}

variable "budget_contact_emails" {
  type    = list(string)
  default = []
}

variable "enable_locks" {
  type    = bool
  default = true
}
