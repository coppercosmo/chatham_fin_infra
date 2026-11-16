# Offline tests for the Tier 3 pooled stamp (mocked provider). The pooled app is shared, so these assert
# the controls that don't depend on its code being right (ADR 0014).

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
    }
  }
  mock_resource "azurerm_api_management" {
    defaults = {
      gateway_url          = "https://apim-pool01-prd-eus2-ab12.azure-api.net"
      private_ip_addresses = ["10.120.1.68"]
    }
  }
  mock_resource "azurerm_container_app_environment" {
    defaults = {
      default_domain    = "quiet-lake-456.eastus2.azurecontainerapps.io"
      static_ip_address = "10.120.0.10"
    }
  }
}

variables {
  pool                      = "pool01"
  subscription_id           = "11111111-1111-1111-1111-111111111111"
  address_space             = "10.120.0.0/22"
  cost_center               = "AI-ADVISORY-POOL01"
  owner_email               = "platform@example.com"
  host_name                 = "advisor.ai.chatham.example.com"
  certificate_secret_id     = "https://kv-pool01.vault.azure.net/secrets/advisor-ai-tls"
  app_image                 = "craiadv.azurecr.io/advisor-api@sha256:2222222222222222222222222222222222222222222222222222222222222222"
  ingest_image              = "craiadv.azurecr.io/advisor-ingest@sha256:3333333333333333333333333333333333333333333333333333333333333333"
  app_api_audience          = "api://ai-advisory-pooled"
  user_token_client_app_ids = ["f0000000-0000-0000-0000-00000000000f"]
  tenants = {
    contoso   = { users_group_object_id = "10000000-0000-0000-0000-000000000001" }
    adatum    = { users_group_object_id = "20000000-0000-0000-0000-000000000002", data_classification = "public" }
    proseware = { users_group_object_id = "30000000-0000-0000-0000-000000000003" }
  }
}

run "pooled_app_identity_has_no_data_roles" {
  command = plan

  assert {
    condition     = toset(output.app_identity_roles) == toset(["metrics"])
    error_message = "The pooled app's own identity must have no storage, search, vault or model role: data is read on the user's token."
  }
}

run "each_tenant_group_reads_only_its_own_container_and_index" {
  command = plan

  assert {
    condition = alltrue([for k, t in var.tenants :
      azurerm_role_assignment.tenant_users_blob[k].principal_id == t.users_group_object_id &&
      azurerm_role_assignment.tenant_users_blob[k].role_definition_name == "Storage Blob Data Reader" &&
      azurerm_role_assignment.tenant_users_index[k].principal_id == t.users_group_object_id &&
      azurerm_role_assignment.tenant_users_index[k].role_definition_name == "Search Index Data Reader"
    ])
    error_message = "A tenant's group gets read on its own container and index (scopes: .../containers/<tenant>, .../indexes/<tenant>)."
  }
  assert {
    condition     = alltrue([for k, c in azurerm_storage_container.tenant : c.name == k && c.default_encryption_scope == k && c.encryption_scope_override_enabled == false])
    error_message = "Each tenant's container is encrypted with its own scope, and uploads can't pick another."
  }
}

run "background_work_runs_as_a_per_tenant_identity" {
  command = plan

  assert {
    condition     = length(azurerm_user_assigned_identity.ingest) == 3 && length(azurerm_container_app_job.ingest) == 3
    error_message = "One ingestion identity and one job per tenant."
  }
}

run "gateway_runs_in_pooled_mode" {
  # The rendered policy embeds the ingestion identities' client IDs, which are unknown until apply; its
  # content (tenant from the token only, 403 without one, per-tenant limits) is asserted in
  # modules/ai-gateway/tests. Here: the pool switches that mode on and accepts the user's token.
  command = plan

  assert {
    condition     = module.ai_gateway.pooled == true
    error_message = "The pooled stamp must run its gateway in pooled mode (tenant from the token, per-tenant limits)."
  }
  assert {
    condition     = contains(module.ai_gateway.audiences, "api://ai-advisory-pooled")
    error_message = "The gateway must accept the signed-in user's token for the pooled app's API."
  }
}

run "confidential_data_is_refused" {
  command = plan

  variables {
    tenants = {
      contoso = { users_group_object_id = "10000000-0000-0000-0000-000000000001", data_classification = "confidential" }
    }
  }

  expect_failures = [var.tenants]
}

run "shared_group_is_refused" {
  command = plan

  variables {
    tenants = {
      contoso = { users_group_object_id = "10000000-0000-0000-0000-000000000001" }
      adatum  = { users_group_object_id = "10000000-0000-0000-0000-000000000001" }
    }
  }

  expect_failures = [var.tenants]
}

run "full_pool_is_refused" {
  command = plan

  variables {
    max_tenants = 1
  }

  expect_failures = [var.tenants]
}
