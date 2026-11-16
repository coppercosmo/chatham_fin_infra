# Tier 3 "pooled" (ADR 0014): one multi-tenant app and one set of stores for many low-sensitivity tenants.
# Per tenant: a blob container, a search index, an encryption scope, an ingestion identity and job, and
# role assignments for the tenant's Entra group at container and index scope. All from the tenants map.

variable "pool" {
  type = string
  validation {
    condition     = can(regex("^pool[0-9]{2}$", var.pool))
    error_message = "pool must look like pool01."
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

variable "subscription_id" { type = string }

variable "tags" {
  type    = map(string)
  default = {}
}

variable "cost_center" { type = string }
variable "owner_email" { type = string }

variable "connectivity_mode" {
  type    = string
  default = "standalone"
  validation {
    condition     = contains(["landing_zone", "standalone"], var.connectivity_mode)
    error_message = "connectivity_mode must be landing_zone or standalone."
  }
}

variable "address_space" { type = string }

variable "hub" {
  type = object({
    vnet_id             = string
    firewall_private_ip = string
    dns_servers         = list(string)
  })
  default = null
}

variable "host_name" {
  type        = string
  description = "One host name for every tenant, e.g. advisor.ai.chatham.example.com. The tenant comes from the user's token."
}

variable "certificate_secret_id" {
  type    = string
  default = null
}

variable "app_image" { type = string }

variable "ingest_image" {
  type        = string
  description = "Image for the per-tenant ingestion jobs (same repo as the app, different entry point)."
}

variable "acr" {
  type = object({
    id           = string
    login_server = string
  })
  default = null
}

variable "app_api_audience" {
  type        = string
  description = "Application ID URI of the pooled app's API registration (owned by P&T), e.g. api://ai-advisory-pooled. Users' tokens for it carry the Tenant.<code> role."
}

variable "user_token_client_app_ids" {
  type        = list(string)
  description = "Client application IDs allowed to present a user's token to the AI gateway (the pooled app's front end)."
}

variable "tenant_role_prefix" {
  type    = string
  default = "Tenant."
}

variable "tenants" {
  description = <<-EOT
    users_group_object_id: the tenant's Entra group (P&T-owned). It is assigned the Tenant.<code> app role AND
    is the data permission: Azure checks it at container and index scope on every read.
  EOT
  type = map(object({
    users_group_object_id = string
    data_classification   = optional(string, "internal")
    ingest_schedule       = optional(string, "0 2 * * *")
    cmk_key_id            = optional(string) # Key Vault key for this tenant's encryption scope (crypto-shred on offboarding)
  }))

  validation {
    condition     = alltrue([for k in keys(var.tenants) : can(regex("^[a-z][a-z0-9]{1,11}$", k))])
    error_message = "Tenant codes are 2-12 lowercase letters/digits, starting with a letter (they name containers and indexes)."
  }
  validation {
    condition     = alltrue([for t in values(var.tenants) : contains(["public", "internal"], t.data_classification)])
    error_message = "The pooled tier takes public or internal data only (ADR 0014). Confidential client data goes to Tier 2 or Tier 1."
  }
  validation {
    condition     = length(distinct([for t in values(var.tenants) : t.users_group_object_id])) == length(var.tenants)
    error_message = "Each tenant needs its own Entra group: a shared group would grant one tenant's users another tenant's data."
  }
  validation {
    condition     = length(var.tenants) <= var.max_tenants
    error_message = "This pool is full (max_tenants). Start pool02 rather than raising the cap past the search tier's index limit."
  }
}

variable "max_tenants" {
  description = "One search index per tenant: AI Search S1 allows 50 indexes per service, so the default leaves headroom."
  type        = number
  default     = 45
}

variable "tokens_per_minute_per_tenant" {
  type    = number
  default = 20000
}

variable "monthly_token_quota_per_tenant" {
  type    = number
  default = 0
}

variable "model_deployments" {
  type = map(object({
    model_name    = string
    model_version = string
    sku           = optional(string, "DataZoneStandard")
    capacity      = optional(number, 10)
  }))
  default = {
    chat       = { model_name = "gpt-4o-mini", model_version = "2024-07-18", capacity = 100 }
    embeddings = { model_name = "text-embedding-3-large", model_version = "1", capacity = 50 }
  }
}

variable "ai_gateway_sku" {
  type    = string
  default = "Developer_1"
}

variable "app_min_replicas" {
  type    = number
  default = 2
}

variable "zone_redundant" {
  type    = bool
  default = true
}

variable "log_retention_days" {
  type    = number
  default = 90
}
