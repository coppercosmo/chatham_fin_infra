# Plans the reference hub with the example clients (mocked provider, no Azure access).
# Run with: terraform test -var-file=terraform.tfvars.example

mock_provider "azurerm" {
  mock_data "azurerm_key_vault_secret" {
    defaults = { value = "mock-secret" }
  }
  mock_resource "azurerm_firewall" {
    defaults = {
      ip_configuration = [{ name = "default", subnet_id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/AzureFirewallSubnet", public_ip_address_id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg/providers/Microsoft.Network/publicIPAddresses/pip", private_ip_address = "10.0.0.4" }]
    }
  }
  mock_resource "azurerm_virtual_network" {
    defaults = { id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-connectivity-hub-eus2/providers/Microsoft.Network/virtualNetworks/vnet-hub-eus2" }
  }
  mock_resource "azurerm_private_dns_resolver_inbound_endpoint" {
    defaults = {
      ip_configurations = [{ subnet_id = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-dns-inbound", private_ip_address = "10.0.1.4", private_ip_allocation_method = "Static" }]
    }
  }
}

run "example_clients_plan_cleanly" {
  command = plan

  assert {
    condition     = join(",", sort(keys(output.client_handout))) == "acme,fabrikam"
    error_message = "Only the ExpressRoute and VPN example clients need anything from the hub beyond peering."
  }
  assert {
    condition     = azurerm_subnet.gateway.address_prefixes[0] == "10.0.0.64/26" && module.connectivity.dns_forwarder_ip == "10.0.1.4"
    error_message = "Hub layout must match the hub values the client configs use."
  }
}
