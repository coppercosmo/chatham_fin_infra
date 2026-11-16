output "private_endpoint_ips" {
  description = "Private IP of each endpoint (what the names resolve to inside the VNet)."
  value       = { for k, pe in azurerm_private_endpoint.this : k => pe.private_service_connection[0].private_ip_address }
}

output "subnet_prefixes" {
  value = local.subnets
}

output "dns_zones" {
  value = sort(keys(azurerm_private_dns_zone.this))
}
