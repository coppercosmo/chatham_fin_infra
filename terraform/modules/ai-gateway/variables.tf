variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tenant_id" { type = string }
variable "client" { type = string }
variable "tags" { type = map(string) }

variable "sku_name" {
  type        = string
  default     = "Developer_1"
  description = <<-EOT
    Developer_1 for dev/demo (internal VNet, no SLA, ~USD 50/month). Premium_1 (zone redundant, SLA)
    for production clients. StandardV2 with private endpoint + VNet integration is the cheaper
    production option to evaluate (ADR 0012).
  EOT
}

variable "zones" {
  type        = list(string)
  default     = null
  description = "Premium only."
}

variable "publisher_name" {
  type    = string
  default = "Chatham AI Advisory"
}

variable "publisher_email" { type = string }

variable "subnet_id" {
  type        = string
  description = "Dedicated snet-apim subnet (internal VNet mode)."
}

variable "vnet_id" {
  type        = string
  description = "Spoke VNet to link the gateway's private DNS zone to."
}

variable "backends" {
  description = <<-EOT
    Azure OpenAI backends in failover order (first = primary, e.g. the PTU account; later = pay-as-you-go
    or another region in the same data zone). url is the account endpoint, e.g. https://oai-x.openai.azure.com/
  EOT
  type = list(object({
    name        = string
    url         = string
    resource_id = string
  }))
  validation {
    condition     = length(var.backends) >= 1
    error_message = "At least one backend is required."
  }
}

variable "allowed_caller_client_ids" {
  type        = list(string)
  description = "Managed identity client IDs allowed to call the gateway (the client's app identity)."
}

variable "tokens_per_minute" {
  type        = number
  default     = 50000
  description = "llm-token-limit per caller. Protects the client's quota from one runaway workload."
}

variable "monthly_token_quota" {
  type        = number
  default     = 0
  description = "Hard monthly token quota per caller; 0 = no quota (use budgets instead)."
}

variable "log_request_bodies_bytes" {
  type        = number
  default     = 0
  description = <<-EOT
    Bytes of prompt/response bodies to log. 0 by default (data minimisation). Turning this on stores
    client prompts in the client's workspace; it's a per-client decision recorded with the client.
  EOT
}

variable "enable_content_safety" {
  type        = bool
  default     = false
  description = "Screen prompts with Azure AI Content Safety (Prompt Shields) via llm-content-safety (preview policy)."
}

variable "content_safety_name" {
  type    = string
  default = null
}

variable "pe_subnet_id" {
  type    = string
  default = null
}

variable "cognitiveservices_private_dns_zone_ids" {
  type    = list(string)
  default = []
}

variable "log_analytics_workspace_id" { type = string }
variable "app_insights_id" { type = string }
variable "app_insights_connection_string" {
  type      = string
  sensitive = true
}
