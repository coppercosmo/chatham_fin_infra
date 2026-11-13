output "resource_group" { value = azurerm_resource_group.this.name }
output "vnet_id" { value = module.network.vnet_id }
output "openai_endpoint" { value = module.ai.openai_endpoint }
output "model_deployments" { value = module.ai.deployment_names }
output "key_vault_uri" { value = module.key_vault.uri }
output "api_internal_fqdn" { value = module.apps.api_fqdn }
output "api_internal_ip" { value = module.apps.environment_static_ip }
output "app_identity_client_id" { value = module.app_identity.client_id }
output "private_endpoint_ips" {
  value = { for k, pe in module.private_endpoint : k => pe.private_ip }
}
