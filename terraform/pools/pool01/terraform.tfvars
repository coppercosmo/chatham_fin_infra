# Tier 3 pooled (ADR 0014): one multi-tenant app for low-sensitivity tenants. A new tenant is one map entry
# plus a P&T-owned Entra group assigned the Tenant.<code> app role.
pool            = "pool01"
location        = "eastus2"
subscription_id = "66666666-6666-6666-6666-666666666666"

connectivity_mode = "landing_zone"
address_space     = "10.120.0.0/22"
hub = {
  vnet_id             = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-connectivity-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub-eus2"
  firewall_private_ip = "10.0.0.4"
  dns_servers         = ["10.0.1.4"]
}

host_name             = "advisor.ai.chatham.example.com"
certificate_secret_id = "https://kv-pool01-prd-eus2-ab12.vault.azure.net/secrets/advisor-ai-tls"

app_image    = "craiadvx7k2.azurecr.io/advisor-api@sha256:0000000000000000000000000000000000000000000000000000000000000000"
ingest_image = "craiadvx7k2.azurecr.io/advisor-ingest@sha256:0000000000000000000000000000000000000000000000000000000000000000"
acr = {
  id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aiadv-platform/providers/Microsoft.ContainerRegistry/registries/craiadvx7k2"
  login_server = "craiadvx7k2.azurecr.io"
}

# P&T-owned app registration for the pooled app (app roles Tenant.<code>).
app_api_audience          = "api://ai-advisory-pooled"
user_token_client_app_ids = ["f0000000-0000-0000-0000-00000000000f"] # the pooled app's web front end

tokens_per_minute_per_tenant   = 20000
monthly_token_quota_per_tenant = 50000000

tenants = {
  contoso   = { users_group_object_id = "10000000-0000-0000-0000-000000000001" }                                 # trial of the hedge-explainer tool
  adatum    = { users_group_object_id = "20000000-0000-0000-0000-000000000002", data_classification = "public" } # market-commentary Q&A
  proseware = { users_group_object_id = "30000000-0000-0000-0000-000000000003" }
  chatham   = { users_group_object_id = "40000000-0000-0000-0000-000000000004" } # internal staff tools
}

cost_center = "AI-ADVISORY-POOL01"
owner_email = "ai-platform@example.com"
