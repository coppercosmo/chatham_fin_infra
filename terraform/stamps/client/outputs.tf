output "resource_group" { value = azurerm_resource_group.this.name }
output "vnet_id" { value = module.network.vnet_id }
output "compute_platform" { value = var.compute_platform }
output "openai_endpoint" { value = module.ai.openai_endpoint }
output "model_deployments" { value = module.ai.deployment_names }
output "key_vault_uri" { value = module.key_vault.uri }
output "app_identity_client_id" { value = module.app_identity.client_id }
output "private_endpoint_ips" {
  value = { for k, pe in module.private_endpoint : k => pe.private_ip }
}

# Container Apps
output "api_internal_fqdn" { value = try(module.apps[0].api_fqdn, null) }
output "api_internal_ip" { value = try(module.apps[0].environment_static_ip, null) }

# AKS
output "aks_cluster_name" { value = try(module.aks[0].name, null) }
output "aks_private_fqdn" { value = try(module.aks[0].private_fqdn, null) }
output "aks_ingress_internal_ip" { value = local.use_aks ? local.aks_ingress_ip : null }
output "app_settings" {
  description = "Values for the app ConfigMap on AKS (kubernetes/app.yaml)."
  value       = local.app_settings
}

# Ingress
output "ingress_private_ip" { value = try(module.ingress[0].private_ip, null) }
output "ingress_public_ip" { value = try(module.ingress[0].public_ip, null) }

# AI gateway
output "ai_gateway_url" { value = try(module.ai_gateway[0].gateway_url, null) }
output "ai_gateway_private_dns_zone_id" {
  description = "Landing-zone mode: ask P&T to link this zone to the hub DNS resolver VNet."
  value       = try(module.ai_gateway[0].private_dns_zone_id, null)
}
