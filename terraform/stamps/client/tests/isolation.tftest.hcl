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
  mock_resource "azurerm_api_management" {
    defaults = {
      gateway_url          = "https://apim-testco-prd-eus2-ab12.azure-api.net"
      private_ip_addresses = ["10.100.1.68"]
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

run "ai_gateway_is_internal_and_the_only_path_to_models" {
  command = plan

  variables {
    ai_gateway = {
      enable_content_safety = true
    }
  }

  assert {
    condition     = module.ai_gateway[0].virtual_network_type == "Internal"
    error_message = "The AI gateway must run in internal VNet mode (private VIP only)."
  }
  assert {
    condition     = !contains(module.app_identity.role_keys, "openai")
    error_message = "With the gateway on, the app must not have direct Azure OpenAI access (no bypass)."
  }
  assert {
    condition     = contains(keys(azurerm_private_dns_zone.this), "cognitiveservices")
    error_message = "Content Safety needs its privatelink zone in standalone mode."
  }
}

run "without_gateway_app_calls_model_directly" {
  command = plan

  assert {
    condition     = contains(module.app_identity.role_keys, "openai") && length(module.ai_gateway) == 0
    error_message = "Without the gateway the app keeps its direct, least-privilege model role."
  }
}

# ---------------------------------------------------------------- client network connectivity (ADR 0013)

run "no_client_connectivity_changes_nothing" {
  command = plan

  variables {
    ingress = {
      host_name             = "testco.ai.example.com"
      certificate_secret_id = "https://kv-testco.vault.azure.net/secrets/testco-tls"
    }
  }

  assert {
    condition     = output.hub_connectivity_request == null && output.private_link_offer == null
    error_message = "With client_connectivity = none there is nothing to hand to P&T or to the client."
  }
  assert {
    condition     = join(",", output.ingress_allowed_sources) == "VirtualNetwork" && !module.network.uses_remote_gateways
    error_message = "Default ingress sources and peering must be unchanged when no client network is connected."
  }
}

run "expressroute_client_is_admitted_only_from_its_own_ranges" {
  command = plan

  variables {
    connectivity_mode = "landing_zone"
    hub = {
      vnet_id             = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
      firewall_private_ip = "10.0.0.4"
      dns_servers         = ["10.0.1.4"]
      gateway_transit     = true
    }
    ingress = {
      host_name             = "testco.ai.example.com"
      certificate_secret_id = "https://kv-testco.vault.azure.net/secrets/testco-tls"
    }
    client_connectivity = {
      type             = "expressroute"
      on_prem_prefixes = ["172.16.0.0/16", "192.168.10.0/24"]
      expressroute = {
        circuit_id = "/subscriptions/99999999-9999-9999-9999-999999999999/resourceGroups/rg-er/providers/Microsoft.Network/expressRouteCircuits/er-testco"
      }
    }
  }

  assert {
    condition     = join(",", output.ingress_allowed_sources) == "172.16.0.0/16,192.168.10.0/24"
    error_message = "The App Gateway NSG must admit only this client's network, never the VirtualNetwork tag (it matches every client the hub gateway knows)."
  }
  assert {
    condition     = join(",", module.network.agw_routes_via_firewall) == "172.16.0.0/16,192.168.10.0/24"
    error_message = "Replies to the client's network must go back through the hub firewall (symmetric routing)."
  }
  assert {
    condition     = module.network.uses_remote_gateways
    error_message = "With gateway transit agreed, the spoke must use the hub gateway."
  }
  assert {
    condition     = output.hub_connectivity_request.ingress_ip == "10.100.2.10" && output.hub_connectivity_request.spoke_prefix == "10.100.0.0/22"
    error_message = "The request to P&T must carry the spoke range and the App Gateway private IP."
  }
  assert {
    condition     = output.private_link_offer == null && !module.ingress[0].private_link_enabled
    error_message = "A routed client must not also get Private Link."
  }
}

run "vpn_client_with_nat_waits_for_gateway_transit" {
  command = plan

  variables {
    connectivity_mode = "landing_zone"
    hub = {
      vnet_id             = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
      firewall_private_ip = "10.0.0.4"
      dns_servers         = ["10.0.1.4"]
    }
    ingress = {
      host_name             = "testco.ai.example.com"
      certificate_secret_id = "https://kv-testco.vault.azure.net/secrets/testco-tls"
    }
    client_connectivity = {
      type             = "vpn"
      on_prem_prefixes = ["100.64.12.0/24"]
      vpn = {
        device_public_ip = "203.0.113.10"
        nat              = [{ client_prefix = "10.0.0.0/24", azure_prefix = "100.64.12.0/24" }]
      }
    }
  }

  # The check block warns that the client can't reach the spoke yet; that warning is the point.
  expect_failures = [check.gateway_transit_for_routed_clients]

  assert {
    condition     = !module.network.uses_remote_gateways
    error_message = "Gateway transit stays off until P&T has applied their side (hub.gateway_transit)."
  }
  assert {
    condition     = output.hub_connectivity_request.vpn.nat[0].azure_prefix == "100.64.12.0/24"
    error_message = "NAT mappings must be passed to P&T in the request."
  }
  assert {
    condition     = module.ingress[0].waf_mode == "Prevention" && join(",", output.ingress_allowed_sources) == "100.64.12.0/24"
    error_message = "Azure-side controls must use the translated (post-NAT) range."
  }
}

run "private_link_client_needs_no_hub" {
  command = plan

  variables {
    connectivity_mode = "standalone"
    ingress = {
      host_name             = "testco.ai.example.com"
      certificate_secret_id = "https://kv-testco.vault.azure.net/secrets/testco-tls"
    }
    client_connectivity = {
      type         = "privatelink"
      private_link = { consumer_subscription_ids = ["88888888-8888-8888-8888-888888888888"] }
    }
  }

  assert {
    condition     = module.ingress[0].private_link_enabled && module.ingress[0].listener_frontend == "private"
    error_message = "Private Link must attach to the private frontend; nothing listens on the public IP."
  }
  assert {
    condition     = join(",", output.ingress_allowed_sources) == "10.100.1.128/27"
    error_message = "With Private Link, the App Gateway NSG admits only the Private Link subnet."
  }
  assert {
    condition     = output.private_link_offer.target_sub_resource == "private" && output.hub_connectivity_request == null
    error_message = "The client needs the gateway ID and the 'private' sub-resource; P&T's hub needs nothing."
  }
}

run "routed_client_requires_landing_zone" {
  command = plan

  variables {
    connectivity_mode = "standalone"
    ingress = {
      host_name             = "testco.ai.example.com"
      certificate_secret_id = "https://kv-testco.vault.azure.net/secrets/testco-tls"
    }
    client_connectivity = {
      type             = "vpn"
      on_prem_prefixes = ["172.16.0.0/16"]
      vpn              = { device_public_ip = "203.0.113.10" }
    }
  }

  expect_failures = [terraform_data.client_connectivity_contract]
}

run "client_network_overlapping_the_spoke_is_refused" {
  command = plan

  variables {
    connectivity_mode = "landing_zone"
    hub = {
      vnet_id             = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
      firewall_private_ip = "10.0.0.4"
      dns_servers         = ["10.0.1.4"]
      gateway_transit     = true
    }
    ingress = {
      host_name             = "testco.ai.example.com"
      certificate_secret_id = "https://kv-testco.vault.azure.net/secrets/testco-tls"
    }
    client_connectivity = {
      type             = "expressroute"
      on_prem_prefixes = ["10.0.0.0/8"] # contains the spoke 10.100.0.0/22
      expressroute     = { circuit_id = "/subscriptions/99999999-9999-9999-9999-999999999999/resourceGroups/rg-er/providers/Microsoft.Network/expressRouteCircuits/er-testco" }
    }
  }

  expect_failures = [terraform_data.client_connectivity_contract]
}

run "connectivity_type_block_must_match" {
  command = plan

  variables {
    client_connectivity = {
      type             = "vpn"
      on_prem_prefixes = ["172.16.0.0/16"]
    }
  }

  expect_failures = [var.client_connectivity]
}
