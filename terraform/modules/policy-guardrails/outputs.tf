output "initiative_id" {
  description = "Policy set definition ID, for P&T to assign elsewhere (e.g. a sandbox MG) if they want."
  value       = azurerm_management_group_policy_set_definition.guardrails.id
}

output "assignment_id" {
  value = azurerm_management_group_policy_assignment.guardrails.id
}

output "assignment_principal_id" {
  description = "Managed identity used for remediation tasks."
  value       = azurerm_management_group_policy_assignment.guardrails.identity[0].principal_id
}

output "definition_ids" {
  value = { for k, d in azurerm_policy_definition.this : k => d.id }
}

output "reference_ids" {
  description = "Rule names inside the initiative: use these in exemptions and compliance queries."
  value       = sort(keys(local.references))
}
