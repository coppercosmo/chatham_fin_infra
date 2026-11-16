# Offline: terraform init -backend=false && terraform test (mocked provider, no Azure access).
mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
    }
  }
}

variables {
  subscription_id = "11111111-1111-1111-1111-111111111111"
  prefix          = "demo"
}

run "endpoints_dns_and_nsg" {
  command = plan

  assert {
    condition     = output.subnet_prefixes == { workload = "10.50.0.0/24", pe = "10.50.1.0/24" }
    error_message = "The /22 should split into two /24s."
  }
  assert {
    condition     = toset(keys(azurerm_private_endpoint.this)) == toset(["blob", "vault"])
    error_message = "One private endpoint per service."
  }
  assert {
    condition     = toset(output.dns_zones) == toset(["privatelink.blob.core.windows.net", "privatelink.vaultcore.azure.net"])
    error_message = "Each endpoint type needs its privatelink zone."
  }
  assert {
    condition     = length(azurerm_private_dns_zone_virtual_network_link.this) == 2 && alltrue([for l in azurerm_private_dns_zone_virtual_network_link.this : l.registration_enabled == false])
    error_message = "Every zone must be linked to the VNet, or names resolve to public IPs."
  }
  assert {
    condition     = azurerm_subnet.this["pe"].private_endpoint_network_policies == "Enabled"
    error_message = "Network policies must be on for the endpoint subnet, or the NSG doesn't apply to endpoints."
  }
  assert {
    condition     = azurerm_storage_account.this.public_network_access_enabled == false && azurerm_storage_account.this.shared_access_key_enabled == false
    error_message = "Storage must be private and keyless."
  }
  assert {
    condition     = azurerm_key_vault.this.public_network_access_enabled == false && azurerm_key_vault.this.rbac_authorization_enabled
    error_message = "Key Vault must be private and use RBAC."
  }
}

run "small_address_space_is_refused" {
  command = plan

  variables {
    address_space = "10.50.0.0/24"
  }

  expect_failures = [var.address_space]
}
