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
  gateway_transit     = true # P&T's side applied (onboarding step 3, ADR 0013)
}

# Client network (ADR 0013): acme's analysts come in over acme's own ExpressRoute circuit, linked to
# P&T's hub gateway with an authorization key acme issued (kept in P&T's Key Vault, never here).
# 172.16.0.0/16 is admitted by the hub firewall, the App Gateway NSG and the WAF, to 10.100.6.10:443 only.
client_connectivity = {
  type             = "expressroute"
  on_prem_prefixes = ["172.16.0.0/16"]
  expressroute = {
    circuit_id = "/subscriptions/aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa/resourceGroups/rg-acme-network/providers/Microsoft.Network/expressRouteCircuits/er-acme-nyc"
  }
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

# Document ingestion (ADR 0015): a nightly job, as its own identity, reads acme's documents container, chunks,
# embeds through the AI gateway below and writes acme's index. The app only reads the index.
ingestion = {
  image = "craiadvx7k2.azurecr.io/advisor-ingest@sha256:0000000000000000000000000000000000000000000000000000000000000000"
}

# AI gateway (ADR 0012): the app reaches Azure OpenAI only through APIM. Ring 1 pilot client.
ai_gateway = {
  sku_name              = "Premium_1"
  tokens_per_minute     = 40000
  enable_content_safety = true
}

# Private ingress: users reach acme.ai.<domain> over the hub (ExpressRoute above). The hub's
# private DNS zone for the name points at the App Gateway private IP (10.100.6.10).
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
