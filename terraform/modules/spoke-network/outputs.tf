output "vnet_id" { value = azurerm_virtual_network.this.id }
output "vnet_name" { value = azurerm_virtual_network.this.name }
output "workload_subnet_id" { value = azurerm_subnet.workload.id }
output "workload_subnet_prefix" { value = local.workload_prefix }
output "pe_subnet_id" { value = azurerm_subnet.pe.id }
output "agw_subnet_id" { value = try(azurerm_subnet.agw[0].id, null) }
output "agw_subnet_prefix" { value = var.enable_ingress_subnet ? local.agw_prefix : null }
output "route_table_id" { value = try(azurerm_route_table.this[0].id, null) }
output "forced_tunnel_to_hub" { value = length(azurerm_route_table.this) == 1 }
