# Private, RBAC-mode Key Vault. Holds only genuinely external secrets (ADR 0004).

variable "name" { type = string }
variable "resource_group_name" { type = string }
variable "location" { type = string }
variable "tenant_id" { type = string }
variable "tags" { type = map(string) }

variable "soft_delete_retention_days" {
  type    = number
  default = 90
}

resource "azurerm_key_vault" "this" {
  #checkov:skip=CKV2_AZURE_32:Private endpoint is created by the client stamp (module.private_endpoint["kv"]); Checkov can't follow it across modules. Asserted in stamps/client/tests.
  name                          = var.name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  tenant_id                     = var.tenant_id
  sku_name                      = "premium" # HSM-backed keys available for client CMK
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = var.soft_delete_retention_days
  public_network_access_enabled = false
  tags                          = var.tags

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
}

output "id" { value = azurerm_key_vault.this.id }
output "name" { value = azurerm_key_vault.this.name }
output "uri" { value = azurerm_key_vault.this.vault_uri }
