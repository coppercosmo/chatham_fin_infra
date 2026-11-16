output "id" { value = azurerm_application_gateway.this.id }
output "private_ip" { value = var.private_ip_address }
output "public_ip" { value = try(azurerm_public_ip.this[0].ip_address, null) }
output "waf_policy_id" { value = azurerm_web_application_firewall_policy.this.id }
output "waf_mode" { value = azurerm_web_application_firewall_policy.this.policy_settings[0].mode }
output "frontend_mode" { value = var.frontend_mode }
output "private_link_enabled" { value = local.private_link }
output "private_link_target_sub_resource" {
  description = "Target sub-resource a client uses when creating a private endpoint to this gateway (the frontend IP configuration name)."
  value       = local.private_link ? "private" : null
}
output "listener_frontend" { value = local.listener_fe }
