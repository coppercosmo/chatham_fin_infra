# Shared AI Advisory platform subscription. Holds NO client data (ADR 0001):
# Terraform state, the container registry, and one deployment identity per client.
#
# Bootstrap: the state storage account below is created once with a local backend, then
# state is migrated into it (`terraform init -migrate-state`). See README.

variable "subscription_id" { type = string }
variable "location" {
  type    = string
  default = "eastus2"
}
variable "github_repository" {
  type        = string
  description = "owner/repo that runs the pipelines."
}
variable "name_suffix" {
  type        = string
  description = "Short unique suffix for globally unique names."
}
variable "clients" {
  description = "Every onboarded client: code => dedicated subscription ID."
  type = map(object({
    subscription_id = string
  }))
  default = {}
}
variable "tags" {
  type    = map(string)
  default = {}
}

locals {
  tags = merge(var.tags, { workload = "ai-advisory-platform", managed_by = "terraform", data_classification = "internal" })
}

resource "azurerm_resource_group" "platform" {
  name     = "rg-aiadv-platform"
  location = var.location
  tags     = local.tags
}

# ---- Terraform state: one container per client, so each pipeline identity sees only its own state.
resource "azurerm_storage_account" "state" {
  name                            = "staiadvtfstate${var.name_suffix}"
  resource_group_name             = azurerm_resource_group.platform.name
  location                        = var.location
  account_tier                    = "Standard"
  account_replication_type        = "GZRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  default_to_oauth_authentication = true
  allow_nested_items_to_be_public = false
  # Public endpoint kept on but restricted: GitHub-hosted runners need it until self-hosted
  # runners in the platform VNet are in place. Tighten to private endpoint only after that.
  public_network_access_enabled = true
  tags                          = local.tags

  blob_properties {
    versioning_enabled = true
    delete_retention_policy { days = 30 }
    container_delete_retention_policy { days = 30 }
  }
}

resource "azurerm_storage_container" "platform" {
  name               = "tfstate-platform"
  storage_account_id = azurerm_storage_account.state.id
}

resource "azurerm_storage_container" "client" {
  for_each           = var.clients
  name               = "tfstate-${each.key}"
  storage_account_id = azurerm_storage_account.state.id
}

# ---- Container registry: images are code, not client data.
resource "azurerm_container_registry" "this" {
  name                          = "craiadv${var.name_suffix}"
  resource_group_name           = azurerm_resource_group.platform.name
  location                      = var.location
  sku                           = "Premium" # private endpoints, geo-replication, content trust
  admin_enabled                 = false
  public_network_access_enabled = false
  anonymous_pull_enabled        = false
  tags                          = local.tags
}

# ---- One deployment identity per client (ADR 0004, 0008).
module "deployment_identity" {
  source                   = "../modules/deployment-identity"
  for_each                 = var.clients
  client                   = each.key
  client_subscription_id   = each.value.subscription_id
  resource_group_name      = azurerm_resource_group.platform.name
  location                 = var.location
  github_repository        = var.github_repository
  state_storage_account_id = azurerm_storage_account.state.id
  state_container_name     = azurerm_storage_container.client[each.key].name
  acr_id                   = azurerm_container_registry.this.id
  tags                     = local.tags
}

output "state_storage_account" { value = azurerm_storage_account.state.name }
output "acr" {
  value = {
    id           = azurerm_container_registry.this.id
    login_server = azurerm_container_registry.this.login_server
  }
}
output "deployment_client_ids" {
  description = "Put each value into GitHub Environment client-<code> as AZURE_CLIENT_ID."
  value       = { for k, m in module.deployment_identity : k => m.client_id }
}
output "plan_client_ids" {
  description = "Put each value into GitHub Environment client-<code>-plan as AZURE_CLIENT_ID."
  value       = { for k, m in module.deployment_identity : k => m.plan_client_id }
}
