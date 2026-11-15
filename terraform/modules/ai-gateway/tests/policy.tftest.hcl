# Offline tests for the AI gateway policy (mocked provider). The policy is the security control,
# so its content is asserted, not just its existence.

mock_provider "azurerm" {}

variables {
  name                           = "apim-testco-prd-eus2-ab12"
  resource_group_name            = "rg-testco"
  location                       = "eastus2"
  tenant_id                      = "00000000-0000-0000-0000-000000000000"
  client                         = "testco"
  tags                           = {}
  publisher_email                = "platform@example.com"
  subnet_id                      = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-apim"
  vnet_id                        = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet"
  allowed_caller_client_ids      = ["aaaaaaaa-0000-0000-0000-000000000001"]
  log_analytics_workspace_id     = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg/providers/Microsoft.OperationalInsights/workspaces/log"
  app_insights_id                = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg/providers/Microsoft.Insights/components/appi"
  app_insights_connection_string = "InstrumentationKey=00000000-0000-0000-0000-000000000000"
  backends = [
    { name = "aoai-primary", url = "https://oai-a.openai.azure.com/", resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg/providers/Microsoft.CognitiveServices/accounts/oai-a" },
    { name = "aoai-secondary", url = "https://oai-b.openai.azure.com/", resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg/providers/Microsoft.CognitiveServices/accounts/oai-b" },
  ]
}

run "policy_authenticates_limits_meters_and_fails_over" {
  command = plan

  assert {
    condition     = strcontains(output.policy_xml, "<application-id>aaaaaaaa-0000-0000-0000-000000000001</application-id>")
    error_message = "Only the client's own app identity may call the gateway."
  }
  assert {
    condition     = strcontains(output.policy_xml, "<llm-token-limit") && strcontains(output.policy_xml, "tokens-per-minute=\"50000\"")
    error_message = "Token rate limit must be enforced per caller."
  }
  assert {
    condition     = !strcontains(output.policy_xml, "token-quota=")
    error_message = "No monthly quota unless one is configured."
  }
  assert {
    condition     = strcontains(output.policy_xml, "<llm-emit-token-metric") && strcontains(output.policy_xml, "value=\"testco\"")
    error_message = "Token usage must be emitted with the client dimension for chargeback."
  }
  assert {
    condition     = strcontains(output.policy_xml, "<authentication-managed-identity resource=\"https://cognitiveservices.azure.com\" />")
    error_message = "The gateway must call models with its managed identity, never keys."
  }
  assert {
    condition     = strcontains(output.policy_xml, "count=\"1\"") && strcontains(output.policy_xml, "backend-id=\"aoai-secondary\"")
    error_message = "With two backends, a 429/5xx on the primary must fail over to the secondary."
  }
  assert {
    condition     = !strcontains(output.policy_xml, "llm-content-safety")
    error_message = "Content safety is opt-in."
  }
}

run "single_backend_no_retry_with_quota_and_content_safety" {
  command = plan

  variables {
    backends              = [{ name = "aoai-primary", url = "https://oai-a.openai.azure.com/", resource_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg/providers/Microsoft.CognitiveServices/accounts/oai-a" }]
    monthly_token_quota   = 10000000
    enable_content_safety = true
    content_safety_name   = "cs-testco"
    pe_subnet_id          = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg/providers/Microsoft.Network/virtualNetworks/vnet/subnets/snet-pe"
  }

  assert {
    condition     = !strcontains(output.policy_xml, "<retry")
    error_message = "A single backend needs no failover loop."
  }
  assert {
    condition     = strcontains(output.policy_xml, "token-quota=\"10000000\" token-quota-period=\"Monthly\"")
    error_message = "Configured monthly quota must be rendered."
  }
  assert {
    condition     = strcontains(output.policy_xml, "shield-prompt=\"true\"")
    error_message = "Content safety must run Prompt Shields when enabled."
  }
}
