# Ring 0: Chatham's own internal canary client. Runs standalone so it can be stood up in any
# sandbox subscription without the hub; same stamp, same modules.
client          = "chatham"
environment     = "prd"
location        = "eastus2"
subscription_id = "11111111-1111-1111-1111-111111111111"

connectivity_mode = "standalone"
address_space     = "10.100.0.0/22"
zone_redundant    = false
enable_search     = false
enable_locks      = false

model_deployments = {
  chat = { model_name = "gpt-4o-mini", model_version = "2024-07-18", capacity = 10 }
}

cost_center        = "AI-ADVISORY"
owner_email        = "platform@example.com"
monthly_budget_usd = 300
