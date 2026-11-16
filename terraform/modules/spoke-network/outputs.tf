output "vnet_id" { value = azurerm_virtual_network.this.id }
output "vnet_name" { value = azurerm_virtual_network.this.name }
output "workload_subnet_id" { value = azurerm_subnet.workload.id }
output "workload_subnet_prefix" { value = local.workload_prefix }
output "pe_subnet_id" { value = azurerm_subnet.pe.id }
output "agw_subnet_id" { value = try(azurerm_subnet.agw[0].id, null) }
output "agw_subnet_prefix" { value = var.enable_ingress_subnet ? local.agw_prefix : null }
output "route_table_id" { value = try(azurerm_route_table.this[0].id, null) }
output "forced_tunnel_to_hub" { value = length(azurerm_route_table.this) == 1 }
output "apim_subnet_id" { value = try(azurerm_subnet.apim[0].id, null) }
output "agw_private_link_subnet_id" { value = try(azurerm_subnet.agw_pl[0].id, null) }
output "agw_private_link_subnet_prefix" { value = var.enable_private_link_subnet ? local.agw_pl_prefix : null }
output "agw_allowed_source_prefixes" {
  description = "Sources the App Gateway subnet NSG admits on 443."
  value       = var.enable_ingress_subnet ? local.agw_allowed_sources : []
}
output "agw_routes_via_firewall" {
  description = "Client network ranges App Gateway sends back through the hub firewall."
  value       = length(azurerm_route_table.agw) > 0 ? var.client_network_prefixes : []
}
output "uses_remote_gateways" { value = var.hub != null && var.use_remote_gateways }
