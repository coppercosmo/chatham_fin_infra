output "cell_registration" {
  description = "Paste into the cell's clients map (terraform/cells/<cell>/terraform.tfvars). Identifiers and endpoints only, no secrets."
  value = {
    app_identity_id                = module.app_identity.id
    app_identity_client_id         = module.app_identity.client_id
    app_identity_principal_id      = module.app_identity.principal_id
    gateway_identity_id            = module.gateway_identity.id
    gateway_identity_client_id     = module.gateway_identity.client_id
    openai_endpoint                = module.ai.openai_endpoint
    key_vault_uri                  = module.key_vault.uri
    storage_blob_url               = module.storage.blob_endpoint
    app_insights_connection_string = nonsensitive(module.observability.app_insights_connection_string) # local auth is off: ingestion needs an Entra token
  }
}

output "resource_group_id" { value = data.azurerm_resource_group.this.id }
output "openai_id" { value = module.ai.openai_id }
output "app_identity_roles" { value = module.app_identity.role_keys }
output "gateway_identity_roles" { value = module.gateway_identity.role_keys }
output "openai_public_network_access_enabled" { value = module.ai.openai_public_network_access_enabled }
output "openai_local_auth_enabled" { value = module.ai.openai_local_auth_enabled }
