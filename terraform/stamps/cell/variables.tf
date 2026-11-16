# Tier 2 "shared cell" (ADR 0014): one subscription that holds up to max_clients clients.
# This root owns what the clients share (network, App Gateway, Container Apps environment, AI gateway,
# AI Search, a certificate vault, a workspace for shared-infra logs) and the per-client WIRING on those
# shared resources. Each client's data, keys, models and identities live in terraform/stamps/cell-client.

variable "cell" {
  type        = string
  description = "Cell code, e.g. cell01. Used in names."
  validation {
    condition     = can(regex("^cell[0-9]{2}$", var.cell))
    error_message = "cell must look like cell01."
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
  description = "The cell's subscription, vended once by P&T."
}

variable "tags" {
  type    = map(string)
  default = {}
}

variable "cost_center" { type = string }
variable "owner_email" { type = string }

variable "connectivity_mode" {
  type        = string
  default     = "standalone"
  description = "landing_zone (peered to P&T's hub, DNS by policy) or standalone (own private DNS zones, for demos)."
  validation {
    condition     = contains(["landing_zone", "standalone"], var.connectivity_mode)
    error_message = "connectivity_mode must be landing_zone or standalone."
  }
}

variable "address_space" {
  type        = string
  description = "Cell VNet CIDR from P&T IPAM (a /22, same layout as a Tier 1 spoke)."
}

variable "hub" {
  type = object({
    vnet_id             = string
    firewall_private_ip = string
    dns_servers         = list(string)
    gateway_transit     = optional(bool, false)
  })
  default = null
}

variable "max_clients" {
  type        = number
  default     = 20
  description = "Blast-radius cap. A full cell gets a sibling cell, not more clients."
}

variable "ai_gateway_sku" {
  type        = string
  default     = "Developer_1"
  description = "Developer_1 for pilot cells (no SLA); Premium_1 for production (zones, SLA). Standard v2 is the cheaper option to validate (ADR 0012)."
}

variable "search_sku" {
  type    = string
  default = "standard"
}

variable "search_replica_count" {
  type    = number
  default = 2
}

variable "enable_private_link" {
  type        = bool
  default     = false
  description = "Private Link on the shared App Gateway, for clients that connect from their own Azure subscription."
}

variable "acr" {
  type = object({
    id           = string
    login_server = string
  })
  default = null
}

variable "zone_redundant" {
  type    = bool
  default = true
}

variable "log_retention_days" {
  type    = number
  default = 90
}

variable "client_slots" {
  description = <<-EOT
    Onboarding step 1 (ADR 0014). One entry per client that has a place in this cell, keyed by client code:
    the cell creates the client's resource group and gives that client's OWN deployment identity rights
    there and nowhere else in the cell. Step 2 is terraform/stamps/cell-client, run as that identity.
    Step 3 adds the client to var.clients.
  EOT
  type = map(object({
    deployer_principal_id = string # the client's deployment identity (GitHub environment client-<code>)
    cost_center           = string # resource group tags: resources inherit them (policy)
    owner_email           = string
    data_classification   = optional(string, "confidential")
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.client_slots) : can(regex("^[a-z][a-z0-9]{1,11}$", k))])
    error_message = "Client codes are 2-12 lowercase letters/digits, starting with a letter."
  }
  validation {
    condition     = length(var.client_slots) <= var.max_clients
    error_message = "This cell is full (max_clients). Put the client in a new cell: a cell is a blast-radius boundary."
  }
  validation {
    condition     = alltrue([for s in values(var.client_slots) : contains(["internal", "confidential"], s.data_classification)])
    error_message = "A cell takes internal or confidential data. Highly confidential data needs Tier 1 (ADR 0014)."
  }
  validation {
    condition     = length(distinct(values(var.client_slots)[*].deployer_principal_id)) == length(var.client_slots)
    error_message = "Every client needs its own deployment identity; a shared one could change both clients' data."
  }
}

variable "clients" {
  description = <<-EOT
    One entry per client in the cell. Most fields are pasted from that client's cell-client output
    `cell_registration` (identities, endpoints; no secrets). The rest is edge and capacity config.

    on_prem_prefixes: client ranges routed through P&T's hub (ExpressRoute or VPN), as seen in Azure.
    allowed_client_cidrs: egress IPs for a client on the public frontend.
  EOT
  type = map(object({
    host_name             = string
    certificate_secret_id = string
    frontend              = optional(string, "private")
    allowed_client_cidrs  = optional(list(string), [])
    on_prem_prefixes      = optional(list(string), [])
    waf_mode              = optional(string, "Prevention")
    rate_limit_per_minute = optional(number, 300)
    app_image             = string
    min_replicas          = optional(number, 1)
    max_replicas          = optional(number, 5)
    tokens_per_minute     = optional(number, 50000)
    monthly_token_quota   = optional(number, 0)

    app_identity_id                = string
    app_identity_client_id         = string
    app_identity_principal_id      = string
    gateway_identity_id            = string
    gateway_identity_client_id     = string
    openai_endpoint                = string
    key_vault_uri                  = string
    storage_blob_url               = string
    app_insights_connection_string = string
  }))
  default = {}

  validation {
    condition     = alltrue([for k in keys(var.clients) : can(regex("^[a-z][a-z0-9]{1,11}$", k))])
    error_message = "Client codes are 2-12 lowercase letters/digits, starting with a letter."
  }
  validation {
    condition     = length(var.clients) <= var.max_clients
    error_message = "This cell is full (max_clients). Put the client in a new cell: a cell is a blast-radius boundary."
  }
  validation {
    condition     = length(distinct([for c in values(var.clients) : c.app_identity_client_id])) == length(var.clients) && length(distinct([for c in values(var.clients) : c.gateway_identity_client_id])) == length(var.clients)
    error_message = "Every client needs its own app and gateway identities; two clients can't share one."
  }
  validation {
    condition     = length(distinct([for c in values(var.clients) : lower(c.host_name)])) == length(var.clients)
    error_message = "Two clients can't share a host name: on a shared gateway the host name is what keeps their traffic apart."
  }
}
