variable "openai_name" { type = string }
variable "search_name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }

variable "model_deployments" {
  description = "Model deployments for this client. sku: DataZoneStandard (default), GlobalStandard, Standard, ProvisionedManaged."
  type = map(object({
    model_name    = string
    model_version = string
    sku           = optional(string, "DataZoneStandard")
    capacity      = optional(number, 10) # thousands of tokens per minute
  }))
}

variable "enable_search" {
  type    = bool
  default = true
}

variable "search_sku" {
  type    = string
  default = "basic"
}

variable "search_replica_count" {
  type        = number
  default     = 3
  description = "Azure AI Search SLA needs 2 replicas for queries and 3 for queries + indexing. Non-production clients can use 1."
}

variable "allowed_outbound_fqdns" {
  type        = list(string)
  default     = []
  description = "Extra hosts the OpenAI account may call (e.g. the client's blob endpoint). Search is added automatically."
}
