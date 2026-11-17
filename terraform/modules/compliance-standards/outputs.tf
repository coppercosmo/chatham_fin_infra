output "assigned_standards" {
  description = "Standards assigned at the AI Advisory MG: key => display name, initiative ID and status (ga, preview, thin, superseded, custom)."
  value = merge(
    { for k in var.standards : k => { name = local.catalog[k].name, initiative_id = "${local.initiative_prefix}/${local.catalog[k].guid}", status = local.catalog[k].status } },
    { for k, c in local.custom : k => { name = c.displayName, initiative_id = azurerm_management_group_policy_set_definition.custom[k].id, status = "custom" } },
  )
}

output "assignment_ids" {
  description = "Assignment ID per standard at the MG. Use these to filter compliance queries and to target exemptions."
  value = merge(
    { for k, a in azurerm_management_group_policy_assignment.standard : k => a.id },
    { for k, a in azurerm_management_group_policy_assignment.custom : k => a.id },
  )
}

output "scoped_assignment_ids" {
  description = "Per-client assignments: \"<label>/<standard>\" => assignment ID."
  value = merge(
    { for k, a in azurerm_subscription_policy_assignment.scoped : k => a.id },
    { for k, a in azurerm_resource_group_policy_assignment.scoped : k => a.id },
  )
}

output "catalog" {
  description = "Every built-in standard this module knows, with its verified initiative ID and status."
  value       = { for k, c in local.catalog : k => { name = c.name, initiative_id = "${local.initiative_prefix}/${c.guid}", status = c.status, source = "https://github.com/Azure/azure-policy/blob/master/built-in-policies/policySetDefinitions/${replace(c.file, " ", "%20")}" } }
}
