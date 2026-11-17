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

variable "content_filter" {
  description = <<-EOT
    Content filter (RAI policy) attached to every deployment. Based on Microsoft.Default.
    severity_threshold: harm categories (hate, sexual, self-harm, violence) on prompts and completions are blocked at
      this level and above. Medium is Microsoft's default; Low is stricter. High filters less and is a decision for
      an ADR with the client. Turning filters off needs Microsoft's modified content filtering approval and is not
      offered here.
    indirect_attack_detection: Prompt Shields for documents. On by default here because RAG puts untrusted document
      text in every prompt.
  EOT
  type = object({
    name                      = optional(string, "rag-default")
    severity_threshold        = optional(string, "Medium")
    indirect_attack_detection = optional(bool, true)
  })
  default = {}

  validation {
    condition     = contains(["Low", "Medium", "High"], var.content_filter.severity_threshold)
    error_message = "severity_threshold must be Low, Medium or High."
  }
}
