# Client document store. No shared keys, no public access, Entra ID only.

variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tags" { type = map(string) }

variable "containers" {
  type    = list(string)
  default = ["documents"]
}

variable "replication_type" {
  type    = string
  default = "ZRS"
}

resource "azurerm_storage_account" "this" {
  name                              = var.name
  location                          = var.location
  resource_group_name               = var.resource_group_name
  account_tier                      = "Standard"
  account_replication_type          = var.replication_type
  account_kind                      = "StorageV2"
  min_tls_version                   = "TLS1_2"
  https_traffic_only_enabled        = true
  shared_access_key_enabled         = false
  default_to_oauth_authentication   = true
  public_network_access_enabled     = false
  allow_nested_items_to_be_public   = false
  infrastructure_encryption_enabled = true
  tags                              = var.tags

  blob_properties {
    versioning_enabled = true
    delete_retention_policy { days = 30 }
    container_delete_retention_policy { days = 30 }
  }

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }
}

# Created through the ARM control plane (storage_account_id), so it works with public access
# disabled and from runners outside the VNet.
resource "azurerm_storage_container" "this" {
  for_each              = toset(var.containers)
  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

output "id" { value = azurerm_storage_account.this.id }
output "name" { value = azurerm_storage_account.this.name }
output "blob_endpoint" { value = azurerm_storage_account.this.primary_blob_endpoint }
