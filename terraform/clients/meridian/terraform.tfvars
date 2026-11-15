# Fictional asset manager. Runs on AKS because it self-hosts an open-weight model on GPUs next to
# Azure OpenAI (ADR 0011). Internet-facing for the client's analysts, locked to their egress IPs.
client          = "meridian"
environment     = "prd"
location        = "eastus2"
subscription_id = "55555555-5555-5555-5555-555555555555"

connectivity_mode = "landing_zone"
address_space     = "10.100.8.0/22"
hub = {
  vnet_id             = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-connectivity-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub-eus2"
  firewall_private_ip = "10.0.0.4"
  dns_servers         = ["10.0.1.4"]
}

reader_group_object_id = "66666666-6666-6666-6666-666666666666"
data_classification    = "highly-confidential"

compute_platform = "aks"
aks = {
  private_dns_zone_id    = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-dns/providers/Microsoft.Network/privateDnsZones/privatelink.eastus2.azmk8s.io"
  admin_group_object_ids = ["77777777-7777-7777-7777-777777777777"] # sg-aiadv-meridian-aks-admins (PIM)
  gpu_pool = {
    vm_size   = "Standard_NC24ads_A100_v4"
    min_count = 0
    max_count = 1
  }
}

ingress = {
  host_name               = "meridian.ai.chatham.example.com"
  certificate_secret_id   = "https://kv-meridian-prd-eus2-cd34.vault.azure.net/secrets/meridian-ai-tls"
  frontend_mode           = "public"
  allowed_source_prefixes = ["198.51.100.0/24"] # client's egress range (NSG)
  allowed_client_cidrs    = ["198.51.100.0/24"] # and the WAF, belt and braces
}

model_deployments = {
  chat       = { model_name = "gpt-4o", model_version = "2024-11-20", sku = "DataZoneStandard", capacity = 30 }
  embeddings = { model_name = "text-embedding-3-large", model_version = "1", sku = "DataZoneStandard", capacity = 30 }
}

ai_gateway = {
  sku_name          = "Premium_1"
  tokens_per_minute = 30000
  additional_backends = [{
    name        = "aoai-centralus"
    url         = "https://oai-meridian-prd-cus-ef56.openai.azure.com/"
    resource_id = "/subscriptions/55555555-5555-5555-5555-555555555555/resourceGroups/rg-meridian-prd-cus/providers/Microsoft.CognitiveServices/accounts/oai-meridian-prd-cus-ef56"
  }]
}

acr = {
  id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aiadv-platform/providers/Microsoft.ContainerRegistry/registries/craiadvx7k2"
  login_server = "craiadvx7k2.azurecr.io"
}

cost_center           = "AI-ADVISORY-MERIDIAN"
owner_email           = "meridian-engagement@example.com"
budget_contact_emails = ["meridian-engagement@example.com"]
monthly_budget_usd    = 12000
