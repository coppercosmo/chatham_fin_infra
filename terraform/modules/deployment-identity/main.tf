# Per-client CI/CD identity (ADR 0004, 0008):
# - lives in the shared platform subscription,
# - federated ONLY to the GitHub Environment for that client,
# - Contributor on that client's subscription,
# - RBAC Administrator on that subscription, constrained by an ABAC condition to a fixed
#   list of data-plane roles, so a pipeline can wire up app identities but can never grant Owner.
# - read/write on its own Terraform state container only.
# A second, read-only "plan" identity is federated to the client-<code>-plan environment, used by
# pull requests and drift detection. Unreviewed branches can see a plan but can never apply.

variable "client" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }

variable "client_subscription_id" { type = string }
variable "github_repository" {
  type        = string
  description = "owner/repo"
}
variable "state_storage_account_id" { type = string }
variable "state_container_name" { type = string }
variable "acr_id" {
  type        = string
  default     = null
  description = "Shared ACR. If set, the pipeline may grant AcrPull (and only AcrPull) on it to the client's app identity."
}

locals {
  # Built-in role definition IDs the pipeline may assign.
  assignable_role_ids = [
    "4633458b-17de-408a-b874-0445c86b69e6", # Key Vault Secrets User
    "5e0bd9bd-7b93-4f28-af87-19fc36ad61bd", # Cognitive Services OpenAI User
    "ba92f5b4-2d11-453d-a403-e96b0029c9fe", # Storage Blob Data Contributor
    "1407120a-92aa-4202-b7e9-c0e197c71c8f", # Search Index Data Reader
    "3913510d-42f4-4e42-8a64-420c390055eb", # Monitoring Metrics Publisher
    "2a2b9908-6ea1-4ae2-8e65-a410df84e7d1", # Storage Blob Data Reader (AI Search indexer)
    "acdd72a7-3d63-4fea-9abd-60d6d93d4a2a", # Reader (for P&T-owned reader group)
  ]
  role_list = join(", ", local.assignable_role_ids)

  rbac_condition = <<-EOT
    (
      (
        !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
      )
      OR
      (
        @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.role_list}}
      )
    )
    AND
    (
      (
        !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
      )
      OR
      (
        @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.role_list}}
      )
    )
  EOT
}

resource "azurerm_user_assigned_identity" "this" {
  name                = "id-deploy-${var.client}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = merge(var.tags, { client = var.client })
}

resource "azurerm_federated_identity_credential" "github_env" {
  name                = "github-env-client-${var.client}"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.this.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${var.github_repository}:environment:client-${var.client}"
}

resource "azurerm_role_assignment" "contributor" {
  scope                = "/subscriptions/${var.client_subscription_id}"
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "constrained_rbac_admin" {
  scope                = "/subscriptions/${var.client_subscription_id}"
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  condition            = local.rbac_condition
}

resource "azurerm_role_assignment" "state" {
  scope                = "${var.state_storage_account_id}/blobServices/default/containers/${var.state_container_name}"
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "acr_pull_delegation" {
  count                = var.acr_id == null ? 0 : 1
  scope                = var.acr_id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.this.principal_id
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  condition            = <<-EOT
    (
      (!(ActionMatches{'Microsoft.Authorization/roleAssignments/write'}))
      OR
      (@Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {7f951dda-4ed3-4680-a7ca-43fe172d538d})
    )
    AND
    (
      (!(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'}))
      OR
      (@Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {7f951dda-4ed3-4680-a7ca-43fe172d538d})
    )
  EOT
}

# ---- Read-only plan identity
resource "azurerm_user_assigned_identity" "plan" {
  name                = "id-plan-${var.client}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = merge(var.tags, { client = var.client })
}

resource "azurerm_federated_identity_credential" "github_plan_env" {
  name                = "github-env-client-${var.client}-plan"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.plan.id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${var.github_repository}:environment:client-${var.client}-plan"
}

resource "azurerm_role_assignment" "plan_reader" {
  scope                = "/subscriptions/${var.client_subscription_id}"
  role_definition_name = "Reader"
  principal_id         = azurerm_user_assigned_identity.plan.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "plan_state_reader" {
  scope                = "${var.state_storage_account_id}/blobServices/default/containers/${var.state_container_name}"
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.plan.principal_id
  principal_type       = "ServicePrincipal"
}

output "plan_client_id" { value = azurerm_user_assigned_identity.plan.client_id }
output "client_id" { value = azurerm_user_assigned_identity.this.client_id }
output "principal_id" { value = azurerm_user_assigned_identity.this.principal_id }
