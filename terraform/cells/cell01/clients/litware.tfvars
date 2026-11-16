# Tier 2 client in cell01: its own resource group, data, keys, model account and identities.
# Applied with id-deploy-litware, whose rights stop at this resource group (the cell creates it: client_slots).
client              = "litware"
location            = "eastus2"
subscription_id     = "55555555-5555-5555-5555-555555555555" # the cell's subscription
data_classification = "internal"

cell = {
  name                  = "cell01"
  pe_subnet_id          = "/subscriptions/55555555-5555-5555-5555-555555555555/resourceGroups/rg-cell01-prd-eus2/providers/Microsoft.Network/virtualNetworks/vnet-cell01-prd-eus2/subnets/snet-pe"
  search_service_id     = "/subscriptions/55555555-5555-5555-5555-555555555555/resourceGroups/rg-cell01-prd-eus2/providers/Microsoft.Search/searchServices/srch-cell01-prd-eus2-ab12"
  deployer_principal_id = "dddddddd-0000-0000-0000-00000000000d" # id-deploy-cell01
}

model_deployments = {
  chat       = { model_name = "gpt-4o", model_version = "2024-11-20", capacity = 20 }
  embeddings = { model_name = "text-embedding-3-large", model_version = "1", capacity = 20 }
}

acr = {
  id           = "/subscriptions/00000000-0000-0000-0000-000000000000/resourceGroups/rg-aiadv-platform/providers/Microsoft.ContainerRegistry/registries/craiadvx7k2"
  login_server = "craiadvx7k2.azurecr.io"
}

cost_center           = "AI-ADVISORY-LITWARE"
owner_email           = "litware-engagement@example.com"
budget_contact_emails = ["litware-engagement@example.com"]
monthly_budget_usd    = 800
