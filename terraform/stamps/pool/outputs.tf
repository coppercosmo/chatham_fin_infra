output "app_identity_roles" {
  description = "The pooled app's own roles: no data access (asserted in tests)."
  value       = module.app_identity.role_keys
}

output "gateway_policy_xml" { value = module.ai_gateway.policy_xml }

output "tenants" {
  description = "Per-tenant partitions and identities, for onboarding records and showback."
  value = {
    for k, t in var.tenants : k => {
      container        = k
      index            = k
      encryption_scope = azurerm_storage_encryption_scope.tenant[k].name
      ingest_identity  = azurerm_user_assigned_identity.ingest[k].name
      users_group      = t.users_group_object_id
    }
  }
}

output "app_registration_setup_for_pt" {
  description = "What P&T configures on the pooled app's Entra registration (Terraform here doesn't manage Entra)."
  value = {
    app_roles                 = [for k in keys(var.tenants) : "${var.tenant_role_prefix}${k}"]
    role_assignments          = { for k, t in var.tenants : "${var.tenant_role_prefix}${k}" => t.users_group_object_id }
    federated_credential_note = "Trust the pooled app's managed identity (${local.n.identity_app}) as a federated credential, so the app can do on-behalf-of with no client secret."
  }
}
