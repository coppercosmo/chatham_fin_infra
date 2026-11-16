# Offline tests (mocked provider): the isolation properties of the shared hub (ADR 0013).

mock_provider "azurerm" {
  mock_resource "azurerm_private_dns_resolver_inbound_endpoint" {
    defaults = {
      ip_configurations = [{ subnet_id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub/subnets/snet-dns-inbound", private_ip_address = "10.0.1.4", private_ip_allocation_method = "Static" }]
    }
  }
}

variables {
  name                = "hub-eus2"
  resource_group_name = "rg-connectivity-hub"
  location            = "eastus2"
  hub_vnet_id         = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
  hub_address_space   = ["10.0.0.0/22"]
  gateway_subnet_id   = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub/subnets/GatewaySubnet"
  gateway_route_table = { name = "rt-gateway", resource_group_name = "rg-hub" }
  firewall_private_ip = "10.0.0.4"
  firewall_policy_id  = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-hub/providers/Microsoft.Network/firewallPolicies/afwp-hub"

  expressroute_gateway           = {}
  vpn_gateway                    = {}
  create_dns_resolver            = true
  dns_resolver_inbound_subnet_id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub/subnets/snet-dns-inbound"
  dns_resolver_inbound_ip        = "10.0.1.4"

  clients = {
    acme = {
      type              = "expressroute"
      spoke_vnet_id     = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-acme-prd-eus2/providers/Microsoft.Network/virtualNetworks/vnet-acme-prd-eus2"
      spoke_prefix      = "10.100.4.0/22"
      ingress_ip        = "10.100.6.10"
      host_name         = "acme.ai.chatham.example.com"
      on_prem_prefixes  = ["172.16.0.0/16"]
      firewall_priority = 1000
      expressroute      = { circuit_id = "/subscriptions/99999999-9999-9999-9999-999999999999/resourceGroups/rg-er/providers/Microsoft.Network/expressRouteCircuits/er-acme" }
    }
    fabrikam = {
      type              = "vpn"
      spoke_vnet_id     = "/subscriptions/77777777-7777-7777-7777-777777777777/resourceGroups/rg-fabrikam-prd-eus2/providers/Microsoft.Network/virtualNetworks/vnet-fabrikam-prd-eus2"
      spoke_prefix      = "10.100.12.0/22"
      ingress_ip        = "10.100.14.10"
      host_name         = "fabrikam.ai.chatham.example.com"
      on_prem_prefixes  = ["100.64.12.0/24"]
      firewall_priority = 1010
      vpn = {
        device_public_ip = "203.0.113.10"
        nat              = [{ client_prefix = "172.16.0.0/24", azure_prefix = "100.64.12.0/24" }] # same real range as acme
      }
    }
    meridian = {
      type          = "none"
      spoke_vnet_id = "/subscriptions/55555555-5555-5555-5555-555555555555/resourceGroups/rg-meridian-prd-eus2/providers/Microsoft.Network/virtualNetworks/vnet-meridian-prd-eus2"
      spoke_prefix  = "10.100.8.0/22"
    }
  }
  vpn_shared_keys                 = { fabrikam = "test-only-not-a-real-key" }
  expressroute_authorization_keys = { acme = "00000000-0000-0000-0000-000000000000" }
}

run "each_client_gets_one_door_to_its_own_gateway" {
  command = plan

  assert {
    condition     = join(",", output.routed_clients) == "acme,fabrikam"
    error_message = "Only VPN and ExpressRoute clients get hub connections, routes and firewall rules."
  }
  assert {
    condition     = join(",", output.firewall_rules["acme"].sources) == "172.16.0.0/16" && join(",", output.firewall_rules["acme"].destinations) == "10.100.6.10" && join(",", output.firewall_rules["acme"].ports) == "443"
    error_message = "acme's network may reach acme's App Gateway on 443 and nothing else."
  }
  assert {
    condition     = join(",", output.firewall_rules["fabrikam"].sources) == "100.64.12.0/24"
    error_message = "fabrikam is admitted by its translated (post-NAT) range, so it can't be confused with acme."
  }
  assert {
    condition     = join(",", output.gateway_transit_peerings) == "acme,fabrikam"
    error_message = "Only routed clients' spokes may use the hub gateway; meridian must not learn client routes."
  }
}

run "gateways_are_hardened" {
  command = plan

  assert {
    condition     = azurerm_virtual_network_gateway.vpn[0].bgp_enabled == false && azurerm_virtual_network_gateway_connection.vpn["fabrikam"].bgp_enabled == false
    error_message = "BGP must stay off for client tunnels, or the gateway would pass one client's routes to another."
  }
  assert {
    condition     = azurerm_virtual_network_gateway.er[0].remote_vnet_traffic_enabled == false
    error_message = "VNet-to-VNet traffic over a client's circuit must be off."
  }
  assert {
    condition     = azurerm_virtual_network_gateway_connection.vpn["fabrikam"].ipsec_policy[0].ike_encryption == "AES256" && azurerm_virtual_network_gateway_connection.vpn["fabrikam"].connection_protocol == "IKEv2"
    error_message = "Client tunnels must use IKEv2 with the strong default IPsec policy."
  }
  assert {
    condition     = length(azurerm_virtual_network_gateway_connection.vpn["fabrikam"].ingress_nat_rule_ids) == 1
    error_message = "fabrikam's tunnel must carry its NAT rule."
  }
  assert {
    condition     = length(azurerm_public_ip.vpn) == 2
    error_message = "VPN gateway runs active-active (two public IPs)."
  }
}

run "dns_zone_per_client_and_minimal_routes" {
  command = plan

  assert {
    condition     = length(azurerm_private_dns_zone.client) == 2 && azurerm_private_dns_zone.client["acme"].name == "acme.ai.chatham.example.com"
    error_message = "Each routed client gets a private zone named after its own host name."
  }
  assert {
    condition     = join(",", output.client_handout["acme"].routes_to_azure) == "10.100.6.10/32,10.0.1.4/32"
    error_message = "A client routes only its App Gateway IP and the DNS forwarder toward Azure."
  }
}

run "overlapping_client_networks_are_refused" {
  command = plan

  variables {
    clients = {
      acme = {
        type              = "expressroute"
        spoke_vnet_id     = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-acme-prd-eus2/providers/Microsoft.Network/virtualNetworks/vnet-acme-prd-eus2"
        spoke_prefix      = "10.100.4.0/22"
        ingress_ip        = "10.100.6.10"
        host_name         = "acme.ai.chatham.example.com"
        on_prem_prefixes  = ["172.16.0.0/16"]
        firewall_priority = 1000
        expressroute      = { circuit_id = "/subscriptions/99999999-9999-9999-9999-999999999999/resourceGroups/rg-er/providers/Microsoft.Network/expressRouteCircuits/er-acme" }
      }
      fabrikam = {
        type              = "vpn"
        spoke_vnet_id     = "/subscriptions/77777777-7777-7777-7777-777777777777/resourceGroups/rg-fabrikam-prd-eus2/providers/Microsoft.Network/virtualNetworks/vnet-fabrikam-prd-eus2"
        spoke_prefix      = "10.100.12.0/22"
        ingress_ip        = "10.100.14.10"
        host_name         = "fabrikam.ai.chatham.example.com"
        on_prem_prefixes  = ["172.16.0.0/24"] # inside acme's range, no NAT
        firewall_priority = 1010
        vpn               = { device_public_ip = "203.0.113.10" }
      }
    }
  }

  expect_failures = [terraform_data.checks]
}

run "firewall_priorities_must_be_unique" {
  command = plan

  variables {
    clients = {
      acme = {
        type              = "expressroute"
        spoke_vnet_id     = "/subscriptions/22222222-2222-2222-2222-222222222222/resourceGroups/rg-acme-prd-eus2/providers/Microsoft.Network/virtualNetworks/vnet-acme-prd-eus2"
        spoke_prefix      = "10.100.4.0/22"
        ingress_ip        = "10.100.6.10"
        host_name         = "acme.ai.chatham.example.com"
        on_prem_prefixes  = ["172.16.0.0/16"]
        firewall_priority = 1000
        expressroute      = { circuit_id = "/subscriptions/99999999-9999-9999-9999-999999999999/resourceGroups/rg-er/providers/Microsoft.Network/expressRouteCircuits/er-acme" }
      }
      fabrikam = {
        type              = "vpn"
        spoke_vnet_id     = "/subscriptions/77777777-7777-7777-7777-777777777777/resourceGroups/rg-fabrikam-prd-eus2/providers/Microsoft.Network/virtualNetworks/vnet-fabrikam-prd-eus2"
        spoke_prefix      = "10.100.12.0/22"
        ingress_ip        = "10.100.14.10"
        host_name         = "fabrikam.ai.chatham.example.com"
        on_prem_prefixes  = ["192.168.50.0/24"]
        firewall_priority = 1000
        vpn               = { device_public_ip = "203.0.113.10" }
      }
    }
  }

  expect_failures = [terraform_data.checks]
}
