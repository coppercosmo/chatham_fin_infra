# Offline tests: run with `terraform test` (no Azure credentials needed; the provider is mocked).
# They assert the isolation and security properties the ADRs promise, so a future change that
# re-enables keys or public access fails in CI before it reaches a client.

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
    }
  }
  mock_data "azurerm_subscription" {
    defaults = {
      id = "/subscriptions/11111111-1111-1111-1111-111111111111"
    }
  }
  mock_resource "azurerm_container_app_environment" {
    defaults = {
      default_domain    = "happy-sky-123.eastus2.azurecontainerapps.io"
      static_ip_address = "10.100.0.10"
    }
  }
}

variables {
  client          = "testco"
  subscription_id = "11111111-1111-1111-1111-111111111111"
  address_space   = "10.100.0.0/22"
  cost_center     = "TEST"
  owner_email     = "test@example.com"
}

run "standalone_stamp_is_private_and_keyless" {
  command = plan

  variables {
    connectivity_mode = "standalone"
  }

  assert {
    condition     = module.ai.openai_public_network_access_enabled == false
    error_message = "Azure OpenAI must not have public network access."
  }
  assert {
    condition     = module.ai.openai_local_auth_enabled == false
    error_message = "Azure OpenAI API keys must be disabled."
  }
  assert {
    condition     = length(azurerm_private_dns_zone.this) == 4
    error_message = "Standalone mode must create its own privatelink DNS zones."
  }
  assert {
    condition     = length(module.private_endpoint) == 4
    error_message = "Every data service (kv, blob, oai, search) needs a private endpoint."
  }
  assert {
    condition     = alltrue([for d in values(var.model_deployments) : d.sku != "GlobalStandard"])
    error_message = "Default model deployments must not use GlobalStandard (data residency)."
  }
}

run "landing_zone_defers_dns_to_platform_engineering" {
  command = plan

  variables {
    connectivity_mode = "landing_zone"
    hub = {
      vnet_id             = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
      firewall_private_ip = "10.0.0.4"
      dns_servers         = ["10.0.1.4"]
    }
  }

  assert {
    condition     = length(azurerm_private_dns_zone.this) == 0
    error_message = "In landing-zone mode DNS zones belong to P&T; the stamp must not create them."
  }
  assert {
    condition     = module.network.forced_tunnel_to_hub
    error_message = "In landing-zone mode egress must route through the hub firewall."
  }
}

run "client_code_is_validated" {
  command = plan

  variables {
    client = "Bad_Name!"
  }

  expect_failures = [var.client]
}
