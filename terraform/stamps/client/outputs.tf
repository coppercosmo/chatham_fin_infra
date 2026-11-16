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

# Client network connectivity (ADR 0013)
output "hub_connectivity_request" {
  description = <<-EOT
    VPN/ExpressRoute clients: everything P&T's hub needs for this client, generated from this config so
    nothing is retyped. Goes into the hub's `clients` map (terraform/hub). Secrets (VPN shared key,
    ExpressRoute authorization key) are NOT here; they go straight into P&T's Key Vault.
  EOT
  value = local.client_routed ? {
    client           = var.client
    type             = local.cc.type
    spoke_vnet_id    = module.network.vnet_id
    spoke_prefix     = var.address_space
    ingress_ip       = local.ingress_ip
    host_name        = var.ingress.host_name
    on_prem_prefixes = local.cc.on_prem_prefixes
    vpn              = local.cc.vpn
    expressroute     = local.cc.expressroute
  } : null
}

output "private_link_offer" {
  description = "privatelink clients: what the client needs to create their private endpoint, and whose endpoints we approve."
  value = local.client_private_link ? {
    app_gateway_id            = module.ingress[0].id
    target_sub_resource       = module.ingress[0].private_link_target_sub_resource
    host_name                 = var.ingress.host_name
    consumer_subscription_ids = local.cc.private_link.consumer_subscription_ids
  } : null
}

output "ingress_allowed_sources" {
  description = "Sources admitted on 443 by the App Gateway subnet NSG."
  value       = module.network.agw_allowed_source_prefixes
}
