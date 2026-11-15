output "id" { value = azurerm_api_management.this.id }
output "gateway_url" { value = azurerm_api_management.this.gateway_url }
output "private_ip_addresses" { value = azurerm_api_management.this.private_ip_addresses }
output "principal_id" { value = azurerm_api_management.this.identity[0].principal_id }
output "virtual_network_type" { value = azurerm_api_management.this.virtual_network_type }
output "private_dns_zone_id" {
  description = "Landing-zone mode: P&T links this zone to the hub DNS resolver VNet."
  value       = azurerm_private_dns_zone.gateway.id
}
output "policy_xml" {
  description = "Rendered policy, exposed for tests and review."
  value       = local.policy_xml
}
