# Copy this folder to clients/<code>/ and fill in. Everything else comes from the stamp.
client          = "CHANGEME" # 2-12 lowercase letters/digits
environment     = "prd"
location        = "eastus2"
subscription_id = "CHANGEME" # dedicated subscription vended by P&T

connectivity_mode = "landing_zone"
address_space     = "10.100.0.0/22" # from P&T IPAM
hub = {
  vnet_id             = "/subscriptions/<connectivity>/resourceGroups/<rg>/providers/Microsoft.Network/virtualNetworks/<hub>"
  firewall_private_ip = "10.0.0.4"
  dns_servers         = ["10.0.1.4"]
}

reader_group_object_id = "CHANGEME" # sg-aiadv-<code>-readers (P&T)

compute_platform = "container_apps" # or "aks" (ADR 0011); see clients/meridian for an AKS example

ingress = { # ADR 0010; null = no ingress
  host_name             = "CHANGEME.ai.chatham.example.com"
  certificate_secret_id = "https://<client-kv>.vault.azure.net/secrets/<cert-name>" # versionless
  frontend_mode         = "private"
}

cost_center           = "AI-ADVISORY"
owner_email           = "engagement-lead@example.com"
budget_contact_emails = ["engagement-lead@example.com"]
monthly_budget_usd    = 2000
