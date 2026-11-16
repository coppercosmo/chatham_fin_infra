# Offline tests (mocked provider): one shared App Gateway, a listener and WAF policy per client site.
mock_provider "azurerm" {}

variables {
  name                       = "agw-cell01-prd-eus2"
  identity_name              = "id-cell01-prd-eus2-agw"
  public_ip_name             = "pip-cell01-prd-eus2-agw"
  resource_group_name        = "rg-cell01-prd-eus2"
  location                   = "eastus2"
  tags                       = {}
  subnet_id                  = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-cell01-prd-eus2/providers/Microsoft.Network/virtualNetworks/vnet-cell01-prd-eus2/subnets/snet-agw"
  private_ip_address         = "10.110.2.10"
  key_vault_id               = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-cell01-prd-eus2/providers/Microsoft.KeyVault/vaults/kv-cell01"
  backend_ip                 = "10.110.0.10"
  log_analytics_workspace_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-cell01-prd-eus2/providers/Microsoft.OperationalInsights/workspaces/log-cell01"

  sites = {
    northwind = {
      host_name             = "northwind.ai.chatham.example.com"
      certificate_secret_id = "https://kv-cell01.vault.azure.net/secrets/northwind-ai-tls"
      backend_host_header   = "ca-northwind.internal.calm-river-123.eastus2.azurecontainerapps.io"
      allowed_client_cidrs  = ["172.20.0.0/16"]
    }
    litware = {
      host_name             = "litware.ai.chatham.example.com"
      certificate_secret_id = "https://kv-cell01.vault.azure.net/secrets/litware-ai-tls"
      backend_host_header   = "ca-litware.internal.calm-river-123.eastus2.azurecontainerapps.io"
      frontend              = "public"
      allowed_client_cidrs  = ["203.0.113.0/24"]
      waf_mode              = "Detection"
    }
  }
}

run "each_site_has_its_own_listener_and_waf_policy" {
  command = plan

  assert {
    condition     = toset(keys(azurerm_web_application_firewall_policy.site)) == toset(["northwind", "litware"])
    error_message = "Every client site needs its own WAF policy, so tuning one never changes another."
  }
  assert {
    condition     = azurerm_web_application_firewall_policy.site["litware"].policy_settings[0].mode == "Detection" && azurerm_web_application_firewall_policy.site["northwind"].policy_settings[0].mode == "Prevention"
    error_message = "WAF mode is per site."
  }
  assert {
    condition     = output.listeners["litware"].frontend == "public" && output.listeners["northwind"].frontend == "private"
    error_message = "Frontend choice is per site."
  }
}

run "two_sites_cannot_share_a_host_name" {
  command = plan

  variables {
    sites = {
      a = { host_name = "x.ai.chatham.example.com", certificate_secret_id = "https://kv/secrets/a", backend_host_header = "a.internal" }
      b = { host_name = "X.ai.chatham.example.com", certificate_secret_id = "https://kv/secrets/b", backend_host_header = "b.internal" }
    }
  }

  expect_failures = [var.sites]
}

run "public_site_needs_an_allow_list" {
  command = plan

  variables {
    sites = {
      a = { host_name = "a.ai.chatham.example.com", certificate_secret_id = "https://kv/secrets/a", backend_host_header = "a.internal", frontend = "public" }
    }
  }

  expect_failures = [var.sites]
}
