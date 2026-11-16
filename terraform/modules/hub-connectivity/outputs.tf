output "expressroute_gateway_id" { value = local.er_gateway_id }
output "vpn_gateway_id" { value = local.vpn_gateway_id }
output "vpn_gateway_public_ips" { value = azurerm_public_ip.vpn[*].ip_address }
output "dns_forwarder_ip" { value = local.dns_forwarder_ip }
output "routed_clients" { value = sort(keys(local.routed_clients)) }

output "client_handout" {
  description = <<-EOT
    Per routed client: what their network team needs. Send with the pre-shared key (VPN) through a
    secure channel; the key itself is never in this output.
  EOT
  value = {
    for k, c in local.routed_clients : k => {
      type = c.type
      # Route only these two addresses toward Azure. Nothing else in the hub or spoke answers them.
      routes_to_azure       = compact(["${c.ingress_ip}/32", local.dns_forwarder_ip == null ? "" : "${local.dns_forwarder_ip}/32"])
      host_name             = c.host_name
      dns_conditional_zone  = c.host_name
      dns_forward_to        = local.dns_forwarder_ip
      vpn_peer_ips          = c.type == "vpn" ? azurerm_public_ip.vpn[*].ip_address : null
      vpn_ranges_seen_in_az = c.type == "vpn" ? c.on_prem_prefixes : null
      ipsec_policy          = c.type == "vpn" ? var.ipsec_policy : null
    }
  }
}

output "firewall_rules" {
  description = "Client => the single allow rule P&T's firewall holds for it. Used by tests and audits."
  value = {
    for k, g in azurerm_firewall_policy_rule_collection_group.client : k => {
      sources      = g.network_rule_collection[0].rule[0].source_addresses
      destinations = g.network_rule_collection[0].rule[0].destination_addresses
      ports        = g.network_rule_collection[0].rule[0].destination_ports
    }
  }
}

output "gateway_transit_peerings" {
  value = sort([for k, p in azurerm_virtual_network_peering.to_spoke : k if p.allow_gateway_transit])
}
