# Offline tests for a Tier 2 client resource group (mocked provider). Same data guarantees as a Tier 1
# stamp; the difference is where the network and compute come from (the cell), not how data is protected.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
    }
  }
  # The resource group the cell created (onboarding step 1); a real ID so resources that parse it plan.
  mock_data "azurerm_resource_group" {
    defaults = {
      id       = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-client-prd-eus2"
      location = "eastus2"
    }
  }
}

variables {
  client          = "northwind"
  subscription_id = "11111111-1111-1111-1111-111111111111"
  cost_center     = "AI-ADVISORY-NORTHWIND"
  owner_email     = "northwind-engagement@example.com"
  cell = {
    name                  = "cell01"
    pe_subnet_id          = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-cell01-prd-eus2/providers/Microsoft.Network/virtualNetworks/vnet-cell01-prd-eus2/subnets/snet-pe"
    search_service_id     = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-cell01-prd-eus2/providers/Microsoft.Search/searchServices/srch-cell01-prd-eus2-ab12"
    deployer_principal_id = "dddddddd-0000-0000-0000-00000000000d"
  }
}

run "client_data_is_private_keyless_and_in_its_own_resource_group" {
  command = plan

  assert {
    condition     = output.openai_public_network_access_enabled == false && output.openai_local_auth_enabled == false
    error_message = "The client's Azure OpenAI account must be private and keyless."
  }
  assert {
    condition     = data.azurerm_resource_group.this.name == "rg-northwind-prd-eus2"
    error_message = "Deploys into the resource group the cell created for this client (same naming seed)."
  }
  assert {
    condition     = toset(keys(module.private_endpoint)) == toset(["kv", "blob", "oai"])
    error_message = "The client's vault, storage and model account each get a private endpoint (in the cell's endpoint subnet)."
  }
  assert {
    condition     = local.tags["isolation_tier"] == "2-shared-cell"
    error_message = "Resources carry their isolation tier, for policy and cost reports."
  }
}

run "app_identity_reaches_only_this_clients_data_and_no_model" {
  command = plan

  assert {
    condition     = toset(output.app_identity_roles) == toset(["kv", "blob", "metrics"])
    error_message = "The app identity gets this client's vault, storage and telemetry only. No model role: model calls go through the gateway."
  }
  assert {
    condition     = toset(output.gateway_identity_roles) == toset(["openai"])
    error_message = "The gateway identity can call this client's model account and nothing else."
  }
  assert {
    condition     = length(azurerm_role_assignment.cell_attaches_identity) == 2 && alltrue([for r in azurerm_role_assignment.cell_attaches_identity : r.role_definition_name == "Managed Identity Operator"])
    error_message = "The cell pipeline may attach the identities, nothing more."
  }
}

run "highly_confidential_data_belongs_on_tier_1" {
  command = plan

  variables {
    data_classification = "highly-confidential"
  }

  expect_failures = [var.data_classification]
}

run "own_ptu_capacity_belongs_on_tier_1" {
  command = plan

  variables {
    model_deployments = {
      chat = { model_name = "gpt-4o", model_version = "2024-11-20", sku = "ProvisionedManaged", capacity = 50 }
    }
  }

  expect_failures = [var.model_deployments]
}
