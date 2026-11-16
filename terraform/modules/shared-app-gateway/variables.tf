variable "name" { type = string }
variable "identity_name" { type = string }
variable "public_ip_name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }

variable "zones" {
  type    = list(string)
  default = null
}

variable "subnet_id" { type = string }

variable "private_ip_address" {
  type        = string
  description = "Static private frontend IP shared by every client in the cell."
}

variable "enable_private_link" {
  type        = bool
  default     = false
  description = "Private Link on the private frontend, for clients on Azure (one endpoint per client, in the client's subscription)."
}

variable "private_link_subnet_id" {
  type    = string
  default = null
}

variable "key_vault_id" {
  type        = string
  description = "The cell's certificate vault. Holds TLS certificates for client host names only, never client secrets."
}

variable "backend_ip" {
  type        = string
  description = "Static IP of the shared Container Apps environment. Every site targets it; the host header picks the client's app."
}

variable "sites" {
  description = <<-EOT
    One entry per client in the cell. Each gets its own listener (host name + certificate), its own WAF policy
    (so one client's tuning, allow-list or Detection mode never applies to another) and its own backend settings
    (host header = that client's container app FQDN).
  EOT
  type = map(object({
    host_name                   = string
    certificate_secret_id       = string # versionless Key Vault secret ID in the cell vault
    backend_host_header         = string # ca-<client>.<environment default domain>
    frontend                    = optional(string, "private")
    waf_mode                    = optional(string, "Prevention")
    allowed_client_cidrs        = optional(list(string), [])
    rate_limit_per_minute       = optional(number, 300)
    waf_prompt_field_exclusions = optional(list(string), ["messages", "prompt", "input"])
    health_probe_path           = optional(string, "/")
  }))

  validation {
    condition     = length(var.sites) > 0
    error_message = "A shared gateway needs at least one site."
  }
  validation {
    condition     = alltrue([for s in var.sites : contains(["private", "public"], s.frontend)])
    error_message = "frontend must be private or public."
  }
  validation {
    condition     = alltrue([for s in var.sites : contains(["Detection", "Prevention"], s.waf_mode)])
    error_message = "waf_mode must be Detection or Prevention."
  }
  validation {
    condition     = length(distinct([for s in var.sites : lower(s.host_name)])) == length(var.sites)
    error_message = "Two clients can't share a host name: the host name is what keeps their traffic apart."
  }
  validation {
    condition     = alltrue([for s in var.sites : s.frontend == "private" || length(s.allowed_client_cidrs) > 0])
    error_message = "A client on the public frontend must have allowed_client_cidrs (its egress IPs)."
  }
}

variable "autoscale" {
  type = object({
    min_capacity = number
    max_capacity = number
  })
  default = { min_capacity = 1, max_capacity = 10 }
}

variable "backend_request_timeout_seconds" {
  type    = number
  default = 180
}

variable "log_analytics_workspace_id" {
  type        = string
  description = "The cell workspace (platform ops only). WAF logs include matched fragments, never full bodies."
}
