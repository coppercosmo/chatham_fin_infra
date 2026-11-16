# Tier 2 shared cell (ADR 0014): up to 20 clients share this subscription's edge, compute and AI gateway.
# Each client's data lives in its own resource group (cells/cell01/clients/<client>.tfvars).
cell            = "cell01"
environment     = "prd"
location        = "eastus2"
subscription_id = "55555555-5555-5555-5555-555555555555"

connectivity_mode = "landing_zone"
address_space     = "10.110.0.0/22"
hub = {
  vnet_id             = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-connectivity-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub-eus2"
  firewall_private_ip = "10.0.0.4"
  dns_servers         = ["10.0.1.4"]
  gateway_transit     = true
}

ai_gateway_sku      = "Premium_1"
enable_private_link = true # tailspin connects from its own Azure subscription

acr = {
  id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aiadv-platform/providers/Microsoft.ContainerRegistry/registries/craiadvx7k2"
  login_server = "craiadvx7k2.azurecr.io"
}

cost_center = "AI-ADVISORY-CELL01"
owner_email = "ai-platform@example.com"

# Onboarding step 1: a resource group per client, handed to that client's own deployment identity.
client_slots = {
  northwind = {
    deployer_principal_id = "d1000000-0000-0000-0000-00000000000d"
    cost_center           = "AI-ADVISORY-NORTHWIND"
    owner_email           = "northwind-engagement@example.com"
    data_classification   = "confidential"
  }
  tailspin = {
    deployer_principal_id = "d2000000-0000-0000-0000-00000000000d"
    cost_center           = "AI-ADVISORY-TAILSPIN"
    owner_email           = "tailspin-engagement@example.com"
    data_classification   = "confidential"
  }
  litware = {
    deployer_principal_id = "d3000000-0000-0000-0000-00000000000d"
    cost_center           = "AI-ADVISORY-LITWARE"
    owner_email           = "litware-engagement@example.com"
    data_classification   = "internal"
  }
}

# Step 3, after each client's cell-client run (step 2). Identity and endpoint fields are pasted from that
# run's cell_registration output (placeholders here).
clients = {
  northwind = {
    host_name             = "northwind.ai.chatham.example.com"
    certificate_secret_id = "https://kv-cell01-prd-eus2-ab12.vault.azure.net/secrets/northwind-ai-tls"
    on_prem_prefixes      = ["172.20.0.0/16"] # ExpressRoute through P&T's hub
    app_image             = "craiadvx7k2.azurecr.io/advisor-api@sha256:0000000000000000000000000000000000000000000000000000000000000000"
    tokens_per_minute     = 40000

    app_identity_id                = "/subscriptions/55555555-5555-5555-5555-555555555555/resourceGroups/rg-northwind-prd-eus2/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-northwind-prd-eus2-app"
    app_identity_client_id         = "a1000000-0000-0000-0000-00000000000a"
    app_identity_principal_id      = "a1000000-0000-0000-0000-0000000000aa"
    gateway_identity_id            = "/subscriptions/55555555-5555-5555-5555-555555555555/resourceGroups/rg-northwind-prd-eus2/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-northwind-prd-eus2-gw"
    gateway_identity_client_id     = "a1000000-0000-0000-0000-00000000000b"
    openai_endpoint                = "https://oai-northwind-prd-eus2-1a2b.openai.azure.com/"
    key_vault_uri                  = "https://kv-northwind-prd-eus2-1a2b.vault.azure.net/"
    storage_blob_url               = "https://stnorthwindprdeus21a2b.blob.core.windows.net/"
    app_insights_connection_string = "InstrumentationKey=a1000000-0000-0000-0000-000000000000"
  }
  tailspin = {
    host_name             = "tailspin.ai.chatham.example.com"
    certificate_secret_id = "https://kv-cell01-prd-eus2-ab12.vault.azure.net/secrets/tailspin-ai-tls"
    app_image             = "craiadvx7k2.azurecr.io/advisor-api@sha256:0000000000000000000000000000000000000000000000000000000000000000"
    min_replicas          = 0 # scale to zero between uses
    tokens_per_minute     = 20000

    app_identity_id                = "/subscriptions/55555555-5555-5555-5555-555555555555/resourceGroups/rg-tailspin-prd-eus2/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-tailspin-prd-eus2-app"
    app_identity_client_id         = "b1000000-0000-0000-0000-00000000000a"
    app_identity_principal_id      = "b1000000-0000-0000-0000-0000000000aa"
    gateway_identity_id            = "/subscriptions/55555555-5555-5555-5555-555555555555/resourceGroups/rg-tailspin-prd-eus2/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-tailspin-prd-eus2-gw"
    gateway_identity_client_id     = "b1000000-0000-0000-0000-00000000000b"
    openai_endpoint                = "https://oai-tailspin-prd-eus2-3c4d.openai.azure.com/"
    key_vault_uri                  = "https://kv-tailspin-prd-eus2-3c4d.vault.azure.net/"
    storage_blob_url               = "https://sttailspinprdeus23c4d.blob.core.windows.net/"
    app_insights_connection_string = "InstrumentationKey=b1000000-0000-0000-0000-000000000000"
  }
  litware = {
    host_name             = "litware.ai.chatham.example.com"
    certificate_secret_id = "https://kv-cell01-prd-eus2-ab12.vault.azure.net/secrets/litware-ai-tls"
    frontend              = "public"
    allowed_client_cidrs  = ["203.0.113.0/24"] # litware's egress IPs
    app_image             = "craiadvx7k2.azurecr.io/advisor-api@sha256:0000000000000000000000000000000000000000000000000000000000000000"

    app_identity_id                = "/subscriptions/55555555-5555-5555-5555-555555555555/resourceGroups/rg-litware-prd-eus2/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-litware-prd-eus2-app"
    app_identity_client_id         = "c1000000-0000-0000-0000-00000000000a"
    app_identity_principal_id      = "c1000000-0000-0000-0000-0000000000aa"
    gateway_identity_id            = "/subscriptions/55555555-5555-5555-5555-555555555555/resourceGroups/rg-litware-prd-eus2/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-litware-prd-eus2-gw"
    gateway_identity_client_id     = "c1000000-0000-0000-0000-00000000000b"
    openai_endpoint                = "https://oai-litware-prd-eus2-5e6f.openai.azure.com/"
    key_vault_uri                  = "https://kv-litware-prd-eus2-5e6f.vault.azure.net/"
    storage_blob_url               = "https://stlitwareprdeus25e6f.blob.core.windows.net/"
    app_insights_connection_string = "InstrumentationKey=c1000000-0000-0000-0000-000000000000"
  }
}
