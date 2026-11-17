# One ingestion job design for every tier (ADR 0015). The callers create the identities and their roles, because
# where an identity lives differs by tier (the client's subscription, the client's resource group in a cell, or
# the pool); this module only runs the job as that identity, with the same image and settings contract everywhere.

variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }

variable "container_app_environment_id" {
  type        = string
  description = "Internal Container Apps environment the jobs run in (the client's own in Tier 1, the cell's or pool's otherwise)."
}

variable "workload_profile_name" {
  type    = string
  default = "Consumption"
}

variable "image" {
  type        = string
  description = "Ingestion image, pinned by digest and promoted by ring like the app (same repo, ingestion entry point)."
}

variable "registry_server" {
  type        = string
  default     = null
  description = "ACR login server. Each job pulls with its own identity (AcrPull granted by the caller)."
}

variable "jobs" {
  description = <<-EOT
    One scheduled job per client (Tiers 1 and 2) or tenant (Tier 3), keyed by its code.

    identity_id / identity_client_id: the job's own user-assigned identity. Its roles are the isolation boundary:
      read on this client's documents and write on this client's index, nothing else.
    openai_endpoint: the AI gateway URL for this client, so embedding tokens are limited and metered like chat.
      Only when a client has no gateway is it the model account itself.
    mode: push (read, chunk, embed, write: the default everywhere) or pull (Tier 1 only: apply the AI Search
      indexer, data source and skillset definitions and run the indexer, which reaches storage and the model
      through shared private links).
    manage_index: whether this identity may create or change the index definition. True only where the Search
      service belongs to this client alone (Tier 1); in shared tiers the platform's index admin job does it.
  EOT
  type = map(object({
    identity_id          = string
    identity_client_id   = string
    storage_blob_url     = string
    storage_container    = optional(string, "documents")
    search_endpoint      = string
    search_index         = string
    openai_endpoint      = string
    embedding_deployment = optional(string, "embeddings")
    schedule             = optional(string, "0 2 * * *")
    mode                 = optional(string, "push")
    manage_index         = optional(bool, false)
  }))

  validation {
    condition     = alltrue([for k in keys(var.jobs) : can(regex("^[a-z][a-z0-9]{1,11}$", k))])
    error_message = "Job keys are client or tenant codes: 2-12 lowercase letters/digits, starting with a letter."
  }
  validation {
    condition     = alltrue([for j in values(var.jobs) : contains(["push", "pull"], j.mode)])
    error_message = "mode must be push or pull."
  }
  validation {
    condition     = length(distinct([for j in values(var.jobs) : j.identity_client_id])) == length(var.jobs)
    error_message = "Every client's job needs its own identity; a shared one could read or write another client's data."
  }
  validation {
    condition     = length(distinct([for j in values(var.jobs) : "${j.search_endpoint}|${j.search_index}"])) == length(var.jobs)
    error_message = "Two jobs can't write to the same index."
  }
}

variable "index_admin" {
  description = <<-EOT
    Shared tiers only: a manually started job that creates or updates every listed index definition, as a
    platform identity holding Search Service Contributor on the shared Search service. That role can manage index
    definitions but can't read or load documents. Client and tenant identities never get it, because on a shared
    service it would reach every client's index. Start it after onboarding a client or changing the schema.
  EOT
  type = object({
    identity_id        = string
    identity_client_id = string
    search_endpoint    = string
    indexes            = list(string)
  })
  default = null
}

variable "chunking" {
  description = "Chunk size and overlap in tokens. A common starting point; tune with the retrieval and groundedness evaluations."
  type = object({
    tokens         = optional(number, 512)
    overlap_tokens = optional(number, 128)
  })
  default = {}
}

variable "replica_timeout_in_seconds" {
  type    = number
  default = 3600
}
