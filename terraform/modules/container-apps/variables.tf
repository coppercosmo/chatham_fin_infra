variable "environment_name" { type = string }
variable "infrastructure_resource_group_name" { type = string }
variable "app_name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }

variable "infrastructure_subnet_id" { type = string }
variable "vnet_id" {
  type        = string
  description = "Spoke VNet to link the environment's private DNS zone to."
}
variable "log_analytics_workspace_id" { type = string }

variable "zone_redundant" {
  type    = bool
  default = true
}

variable "identity_id" {
  type        = string
  description = "User-assigned managed identity resource ID for the app."
}
variable "identity_client_id" { type = string }

variable "image" {
  type        = string
  description = "Image reference, ideally pinned by digest. Promoted ring by ring."
}

variable "registry_server" {
  type        = string
  default     = null
  description = "ACR login server; pulled with the app identity (AcrPull). null for public images."
}

variable "target_port" {
  type    = number
  default = 80
}

variable "min_replicas" {
  type    = number
  default = 1
}

variable "max_replicas" {
  type    = number
  default = 5
}

variable "env" {
  type        = map(string)
  default     = {}
  description = "Non-secret environment variables (endpoints, names)."
}

variable "app_insights_connection_string" {
  type      = string
  sensitive = true
}
