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
  mock_resource "azurerm_kubernetes_cluster" {
    defaults = {
      oidc_issuer_url = "https://eastus2.oic.prod-aks.azure.com/00000000-0000-0000-0000-000000000000/11111111-1111-1111-1111-111111111111/"
      web_app_routing = [{
        dns_zone_ids = []
        web_app_routing_identity = [{
          object_id                 = "44444444-4444-4444-4444-444444444444"
          client_id                 = "55555555-5555-5555-5555-555555555555"
          user_assigned_identity_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/webapprouting"
        }]
      }]
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

run "aks_cluster_is_private_entra_only_with_network_policy" {
  command = plan

  variables {
    compute_platform  = "aks"
    connectivity_mode = "landing_zone"
    hub = {
      vnet_id             = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
      firewall_private_ip = "10.0.0.4"
      dns_servers         = ["10.0.1.4"]
    }
  }

  assert {
    condition     = length(module.apps) == 0 && length(module.aks) == 1
    error_message = "compute_platform = aks must build a cluster and no Container Apps environment."
  }
  assert {
    condition     = module.aks[0].private_cluster_enabled && module.aks[0].local_account_disabled
    error_message = "AKS API server must be private and local (non-Entra) accounts disabled."
  }
  assert {
    condition     = module.aks[0].network_policy == "cilium"
    error_message = "AKS must enforce network policy."
  }
  assert {
    condition     = module.aks[0].outbound_type == "userDefinedRouting"
    error_message = "In the landing zone, cluster egress must go through the hub firewall."
  }
}

run "private_ingress_with_waf_in_prevention" {
  command = plan

  variables {
    connectivity_mode = "standalone"
    ingress = {
      host_name             = "testco.ai.example.com"
      certificate_secret_id = "https://kv-testco.vault.azure.net/secrets/testco-tls"
    }
  }

  assert {
    condition     = module.ingress[0].frontend_mode == "private" && module.ingress[0].public_ip == null
    error_message = "Ingress must default to a private frontend with no public IP."
  }
  assert {
    condition     = module.ingress[0].waf_mode == "Prevention"
    error_message = "WAF must default to Prevention mode."
  }
  assert {
    condition     = module.ingress[0].private_ip == "10.100.2.10"
    error_message = "App Gateway private frontend must sit in the dedicated snet-agw subnet."
  }
}

run "aks_ingress_targets_internal_nginx" {
  command = plan

  variables {
    compute_platform = "aks"
    ingress = {
      host_name             = "testco.ai.example.com"
      certificate_secret_id = "https://kv-testco.vault.azure.net/secrets/testco-tls"
      frontend_mode         = "public"
      allowed_client_cidrs  = ["203.0.113.0/24"]
    }
  }

  assert {
    condition     = output.aks_ingress_internal_ip == "10.100.0.250"
    error_message = "AKS ingress must use the static internal LB IP App Gateway targets."
  }
}
