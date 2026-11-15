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
  #checkov:skip=CKV2_AZURE_33:Private endpoint is created by the client stamp (module.private_endpoint["blob"]); Checkov can't follow it across modules. Asserted in stamps/client/tests.
  #checkov:skip=CKV_AZURE_33:No queue service is used. Blob diagnostics go to the client's Log Analytics via the stamp's observability module.
  #checkov:skip=CKV_AZURE_206:ZRS by default keeps data in one region (residency). GZRS is a per-client choice via replication_type.
  #checkov:skip=CKV2_AZURE_1:Microsoft-managed keys plus infrastructure (double) encryption by default. CMK is a per-client contract option (README known gaps).
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
  #checkov:skip=CKV2_AZURE_21:Blob read/write/delete logs are sent to the client's Log Analytics by the stamp (observability.diagnostic_targets.blob).
  for_each              = toset(var.containers)
  name                  = each.value
  storage_account_id    = azurerm_storage_account.this.id
  container_access_type = "private"
}

output "id" { value = azurerm_storage_account.this.id }
output "name" { value = azurerm_storage_account.this.name }
output "blob_endpoint" { value = azurerm_storage_account.this.primary_blob_endpoint }
