output "resource_group_name" { value = azurerm_resource_group.shared.name }

output "cell_inputs_for_clients" {
  description = "What each terraform/stamps/cell-client needs from the cell (paste into its `cell` variable)."
  value = {
    name                   = var.cell
    subscription_id        = var.subscription_id
    pe_subnet_id           = module.network.pe_subnet_id
    search_service_id      = azurerm_search_service.shared.id
    private_dns_zone_ids   = { for k, z in azurerm_private_dns_zone.this : k => z.id }
    gateway_url            = azurerm_api_management.shared.gateway_url
    app_gateway_private_ip = local.agw_private_ip
  }
}

output "hub_connectivity_request" {
  description = "For P&T: one firewall rule per routed client (its ranges -> the cell App Gateway IP:443) and one DNS record per host name."
  value = {
    target_ip = local.agw_private_ip
    clients = {
      for k, c in var.clients : k => {
        host_name        = c.host_name
        on_prem_prefixes = c.on_prem_prefixes
      }
    }
  }
}

output "gateway_policies" {
  description = "Rendered per-client AI gateway policies (asserted in tests)."
  value       = local.gateway_policies
}

output "client_resource_groups" {
  description = "Onboarding step 1 result: the resource group each client's cell-client run deploys into."
  value       = { for k, rg in azurerm_resource_group.client : k => rg.name }
}

output "client_deployer_rbac_condition" {
  description = "The condition on each client deployer's RBAC Administrator role (asserted in tests)."
  value       = local.client_rbac_condition
}

output "client_apps" {
  value = { for k, a in azurerm_container_app.client : k => a.name }
}

output "site_waf_policy_ids" {
  value = length(module.ingress) > 0 ? module.ingress[0].site_waf_policy_ids : {}
}
