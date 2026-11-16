# Fictional bank that already runs in Azure, in its own tenant. Its analysts reach the app through a
# private endpoint woodgrove creates in ITS subscription, connected to woodgrove's App Gateway here
# (Private Link, ADR 0013). Woodgrove's on-prem users ride their existing ExpressRoute to their own
# Azure. Nothing is routed through P&T's hub for them, and their IP ranges don't matter to us.
client          = "woodgrove"
environment     = "prd"
location        = "eastus2"
subscription_id = "99999999-9999-9999-9999-999999999999"

connectivity_mode = "landing_zone" # spoke still uses the hub for egress and DNS
address_space     = "10.100.16.0/22"
hub = {
  vnet_id             = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-connectivity-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub-eus2"
  firewall_private_ip = "10.0.0.4"
  dns_servers         = ["10.0.1.4"]
}

client_connectivity = {
  type = "privatelink"
  private_link = {
    consumer_subscription_ids = ["bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"] # woodgrove's own subscription
  }
}

reader_group_object_id = "99999999-0000-0000-0000-000000000001"
data_classification    = "highly-confidential"

ingress = {
  host_name             = "woodgrove.ai.chatham.example.com"
  certificate_secret_id = "https://kv-woodgrove-prd-eus2-ij90.vault.azure.net/secrets/woodgrove-ai-tls"
  frontend_mode         = "private"
}

ai_gateway = {
  sku_name          = "Premium_1"
  tokens_per_minute = 40000
}

acr = {
  id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aiadv-platform/providers/Microsoft.ContainerRegistry/registries/craiadvx7k2"
  login_server = "craiadvx7k2.azurecr.io"
}

cost_center           = "AI-ADVISORY-WOODGROVE"
owner_email           = "woodgrove-engagement@example.com"
budget_contact_emails = ["woodgrove-engagement@example.com"]
monthly_budget_usd    = 6000
