# Per-client workspace + App Insights (ADR 0009), and diagnostic settings for client resources.

variable "law_name" { type = string }
variable "appi_name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }

variable "retention_in_days" {
  type    = number
  default = 90
}

variable "diagnostic_targets" {
  description = "Resources to send diagnostics from, keyed by a static name (keys must be known at plan time)."
  type        = map(string)
  default     = {}
}

resource "azurerm_log_analytics_workspace" "this" {
  name                         = var.law_name
  location                     = var.location
  resource_group_name          = var.resource_group_name
  sku                          = "PerGB2018"
  retention_in_days            = var.retention_in_days
  local_authentication_enabled = false
  tags                         = var.tags
}

resource "azurerm_application_insights" "this" {
  name                         = var.appi_name
  location                     = var.location
  resource_group_name          = var.resource_group_name
  workspace_id                 = azurerm_log_analytics_workspace.this.id
  application_type             = "web"
  local_authentication_enabled = false
  tags                         = var.tags
}

resource "azurerm_monitor_diagnostic_setting" "this" {
  for_each                   = var.diagnostic_targets
  name                       = "diag-to-client-law"
  target_resource_id         = each.value
  log_analytics_workspace_id = azurerm_log_analytics_workspace.this.id

  enabled_log {
    category_group = "allLogs"
  }

  enabled_metric {
    category = "AllMetrics"
  }
}

output "workspace_id" { value = azurerm_log_analytics_workspace.this.id }
output "app_insights_id" { value = azurerm_application_insights.this.id }
output "app_insights_connection_string" {
  value     = azurerm_application_insights.this.connection_string
  sensitive = true
}
