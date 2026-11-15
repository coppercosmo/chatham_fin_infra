# Fictional insurance client. Ring 1 (pilot). Full landing-zone integration.
client          = "acme"
environment     = "prd"
location        = "eastus2"
subscription_id = "22222222-2222-2222-2222-222222222222"

connectivity_mode = "landing_zone"
address_space     = "10.100.4.0/22"
hub = {
  vnet_id             = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-connectivity-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub-eus2"
  firewall_private_ip = "10.0.0.4"
  dns_servers         = ["10.0.1.4"]
}

reader_group_object_id = "44444444-4444-4444-4444-444444444444"

data_classification = "highly-confidential"
log_retention_days  = 365 # client records policy

model_deployments = {
  chat       = { model_name = "gpt-4o", model_version = "2024-11-20", sku = "DataZoneStandard", capacity = 50 }
  embeddings = { model_name = "text-embedding-3-large", model_version = "1", sku = "DataZoneStandard", capacity = 50 }
}

acr = {
  id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aiadv-platform/providers/Microsoft.ContainerRegistry/registries/craiadvx7k2"
  login_server = "craiadvx7k2.azurecr.io"
}
app_image = "craiadvx7k2.azurecr.io/advisor-api@sha256:0000000000000000000000000000000000000000000000000000000000000000"

# Private ingress: users reach acme.ai.<domain> over the hub (ExpressRoute/VPN or Front Door
# Premium Private Link). P&T's DNS points the name at the App Gateway private IP (10.100.6.10).
ingress = {
  host_name             = "acme.ai.chatham.example.com"
  certificate_secret_id = "https://kv-acme-prd-eus2-ab12.vault.azure.net/secrets/acme-ai-tls"
  frontend_mode         = "private"
  waf_mode              = "Prevention"
  rate_limit_per_minute = 300
}

cost_center           = "AI-ADVISORY-ACME"
owner_email           = "acme-engagement@example.com"
budget_contact_emails = ["acme-engagement@example.com"]
monthly_budget_usd    = 5000
