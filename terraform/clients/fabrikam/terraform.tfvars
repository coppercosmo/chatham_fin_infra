# Fictional regional bank. Connects over site-to-site VPN (no ExpressRoute), and its home network
# uses 172.16.40.0/24, which collides with acme's range, so the hub VPN gateway translates it to a
# unique range from P&T's IPAM (ADR 0013).
client          = "fabrikam"
environment     = "prd"
location        = "eastus2"
subscription_id = "88888888-8888-8888-8888-888888888888"

connectivity_mode = "landing_zone"
address_space     = "10.100.12.0/22"
hub = {
  vnet_id             = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-connectivity-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub-eus2"
  firewall_private_ip = "10.0.0.4"
  dns_servers         = ["10.0.1.4"]
  gateway_transit     = true
}

# IPsec tunnel from fabrikam's firewall (203.0.113.10) to the hub VPN gateway. Inside Azure fabrikam
# is 100.64.12.0/24; at home it keeps 172.16.40.0/24. The pre-shared key is in P&T's Key Vault.
client_connectivity = {
  type             = "vpn"
  on_prem_prefixes = ["100.64.12.0/24"]
  vpn = {
    device_public_ip = "203.0.113.10"
    nat              = [{ client_prefix = "172.16.40.0/24", azure_prefix = "100.64.12.0/24" }]
  }
}

reader_group_object_id = "88888888-0000-0000-0000-000000000001"
data_classification    = "highly-confidential"

ingress = {
  host_name             = "fabrikam.ai.chatham.example.com"
  certificate_secret_id = "https://kv-fabrikam-prd-eus2-gh78.vault.azure.net/secrets/fabrikam-ai-tls"
  frontend_mode         = "private"
}

model_deployments = {
  chat       = { model_name = "gpt-4o", model_version = "2024-11-20", sku = "DataZoneStandard", capacity = 20 }
  embeddings = { model_name = "text-embedding-3-large", model_version = "1", sku = "DataZoneStandard", capacity = 20 }
}

acr = {
  id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aiadv-platform/providers/Microsoft.ContainerRegistry/registries/craiadvx7k2"
  login_server = "craiadvx7k2.azurecr.io"
}

cost_center           = "AI-ADVISORY-FABRIKAM"
owner_email           = "fabrikam-engagement@example.com"
budget_contact_emails = ["fabrikam-engagement@example.com"]
monthly_budget_usd    = 3000
