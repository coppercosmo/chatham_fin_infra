# User-assigned identity for a client workload, with least-privilege data-plane roles
# scoped to individual resources (never the resource group or subscription).

variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }

variable "role_assignments" {
  description = "Static key => { scope, role }. Keys must be known at plan time."
  type = map(object({
    scope = string
    role  = string
  }))
}

resource "azurerm_user_assigned_identity" "this" {
  name                = var.name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "this" {
  for_each                         = var.role_assignments
  scope                            = each.value.scope
  role_definition_name             = each.value.role
  principal_id                     = azurerm_user_assigned_identity.this.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

output "id" { value = azurerm_user_assigned_identity.this.id }
output "client_id" { value = azurerm_user_assigned_identity.this.client_id }
output "principal_id" { value = azurerm_user_assigned_identity.this.principal_id }
