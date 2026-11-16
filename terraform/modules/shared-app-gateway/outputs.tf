output "id" { value = azurerm_application_gateway.this.id }
output "private_ip_address" { value = var.private_ip_address }
output "identity_principal_id" { value = azurerm_user_assigned_identity.agw.principal_id }
output "site_waf_policy_ids" {
  description = "One WAF policy per client: tuning one never changes another."
  value       = { for k, p in azurerm_web_application_firewall_policy.site : k => p.id }
}
output "listeners" {
  value = { for k, s in var.sites : k => { host_name = s.host_name, frontend = s.frontend } }
}
