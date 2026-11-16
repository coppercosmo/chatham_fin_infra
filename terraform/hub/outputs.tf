output "hub_vnet_id" { value = azurerm_virtual_network.hub.id }
output "firewall_private_ip" { value = azurerm_firewall.hub.ip_configuration[0].private_ip_address }
output "dns_forwarder_ip" { value = module.connectivity.dns_forwarder_ip }
output "vpn_gateway_public_ips" { value = module.connectivity.vpn_gateway_public_ips }
output "client_handout" {
  description = "Per client: what to send their network team (routes, DNS, VPN peers, IPsec policy)."
  value       = module.connectivity.client_handout
}
