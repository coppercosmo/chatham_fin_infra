output "openai_id" { value = azurerm_cognitive_account.openai.id }
output "openai_endpoint" { value = azurerm_cognitive_account.openai.endpoint }
output "openai_principal_id" { value = azurerm_cognitive_account.openai.identity[0].principal_id }
output "deployment_names" { value = keys(azurerm_cognitive_deployment.this) }
output "search_id" { value = try(azurerm_search_service.this[0].id, null) }
output "search_endpoint" { value = try("https://${azurerm_search_service.this[0].name}.search.windows.net", null) }
output "search_principal_id" { value = try(azurerm_search_service.this[0].identity[0].principal_id, null) }
output "openai_public_network_access_enabled" { value = azurerm_cognitive_account.openai.public_network_access_enabled }
output "openai_local_auth_enabled" { value = azurerm_cognitive_account.openai.local_auth_enabled }
output "content_filter_name" { value = azurerm_cognitive_account_rai_policy.this.name }
output "content_filters" {
  description = "name/source => { enabled, blocking, severity }, for tests and for the client's records."
  value = {
    for f in local.content_filters : "${f.name}/${f.source}" => { enabled = f.enabled, blocking = f.blocking, severity = f.severity }
  }
}
output "deployment_content_filters" { value = { for k, d in azurerm_cognitive_deployment.this : k => d.rai_policy_name } }
