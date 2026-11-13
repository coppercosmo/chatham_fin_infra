output "environment_id" { value = azurerm_container_app_environment.this.id }
output "environment_static_ip" { value = azurerm_container_app_environment.this.static_ip_address }
output "api_fqdn" { value = azurerm_container_app.api.ingress[0].fqdn }
output "api_id" { value = azurerm_container_app.api.id }
