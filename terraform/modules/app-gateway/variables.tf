variable "name" { type = string }
variable "waf_policy_name" { type = string }
variable "identity_name" { type = string }
variable "public_ip_name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }

variable "subnet_id" {
  type        = string
  description = "Dedicated snet-agw subnet."
}

variable "private_ip_address" {
  type        = string
  description = "Static private frontend IP inside snet-agw. P&T DNS points the client's host name here."
}

variable "frontend_mode" {
  type        = string
  default     = "private"
  description = <<-EOT
    private: private frontend only (users arrive over ExpressRoute/VPN/hub, or via Front Door Premium
             Private Link). Requires the App Gateway network isolation (private-only) deployment.
    public:  public frontend for internet users, WAF in front; NSG limits sources (client CIDRs or Front Door).
  EOT
  validation {
    condition     = contains(["private", "public"], var.frontend_mode)
    error_message = "frontend_mode must be private or public."
  }
}

variable "host_name" {
  type        = string
  description = "Host name clients use, e.g. acme.ai.chathamfinancial.com. SNI is required."
}

variable "key_vault_id" {
  type        = string
  description = "Client Key Vault that holds the TLS certificate."
}

variable "certificate_secret_id" {
  type        = string
  description = "Versionless Key Vault secret ID of the listener certificate, so App Gateway picks up renewals (polls every 4h)."
}

variable "backend_fqdn" {
  type        = string
  default     = null
  description = "Container Apps: the app's internal FQDN. Set this or backend_ip."
}

variable "backend_ip" {
  type        = string
  default     = null
  description = "AKS: the static internal load balancer IP of the in-cluster NGINX ingress."
}

variable "backend_host_header" {
  type        = string
  default     = null
  description = "Host header sent to the backend. null = backend FQDN (Container Apps); AKS uses the client host name."
}

variable "health_probe_path" {
  type    = string
  default = "/healthz"
}

variable "backend_request_timeout_seconds" {
  type        = number
  default     = 180
  description = "LLM completions can take minutes; the default 20s would cut them off."
}

variable "autoscale" {
  type = object({
    min_capacity = number
    max_capacity = number
  })
  default = { min_capacity = 1, max_capacity = 5 }
}

variable "zones" {
  type    = list(string)
  default = ["1", "2", "3"]
}

# ---- WAF
variable "waf_mode" {
  type        = string
  default     = "Prevention"
  description = "Run Detection in ring 0 while tuning exclusions, Prevention everywhere else."
  validation {
    condition     = contains(["Detection", "Prevention"], var.waf_mode)
    error_message = "waf_mode must be Detection or Prevention."
  }
}

variable "waf_max_request_body_kb" {
  type        = number
  default     = 2000
  description = "Prompts with pasted documents are large. DRS 2.1 inspects up to 2 MB bodies."
}

variable "waf_file_upload_limit_mb" {
  type    = number
  default = 100
}

variable "waf_prompt_field_exclusions" {
  type        = list(string)
  default     = ["messages", "prompt", "input"]
  description = <<-EOT
    JSON body fields that carry free-text prompts. Natural language such as "select the top rows from
    the claims table" trips SQL-injection rules. These fields are excluded from the SQLI and XSS rule
    groups only; every other rule still inspects them, and every other field is still checked by SQLI/XSS.
  EOT
}

variable "rate_limit_per_minute" {
  type        = number
  default     = 600
  description = "Per client IP. Protects AOAI quota and cost from a runaway script."
}

variable "allowed_client_cidrs" {
  type        = list(string)
  default     = []
  description = "If set, WAF blocks any source outside these ranges (belt and braces with the NSG)."
}

variable "log_analytics_workspace_id" { type = string }
