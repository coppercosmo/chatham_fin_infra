output "vnet_id" { value = azurerm_virtual_network.this.id }
output "vnet_name" { value = azurerm_virtual_network.this.name }
output "apps_subnet_id" { value = azurerm_subnet.apps.id }
output "pe_subnet_id" { value = azurerm_subnet.pe.id }
output "forced_tunnel_to_hub" { value = length(azurerm_route_table.this) == 1 }
