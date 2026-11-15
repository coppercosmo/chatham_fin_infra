# AI gateway for one client (ADR 0012): Azure API Management in internal VNet mode, sitting between
# the client's app and its Azure OpenAI account(s).
#
#   app (managed identity token) --> APIM (internal, snet-apim) --managed identity--> Azure OpenAI (private endpoint)
#                                     | validate caller, content safety, token limits, token metrics,
#                                     | failover across backends with circuit breakers, logs to client workspace

locals {
  is_premium    = startswith(var.sku_name, "Premium")
  backend_names = [for b in var.backends : b.name]

  policy_xml = templatefile("${path.module}/policy.xml.tftpl", {
    client         = var.client
    tenant_id      = var.tenant_id
    caller_ids     = var.allowed_caller_client_ids
    tpm            = var.tokens_per_minute
    quota          = var.monthly_token_quota
    content_safety = var.enable_content_safety
    backends       = local.backend_names
  })
}

resource "azurerm_api_management" "this" {
  #checkov:skip=CKV_AZURE_107:Callers authenticate with Entra tokens (validate-azure-ad-token), not APIM subscription keys, so subscription_required is off by design.
  #checkov:skip=CKV_AZURE_174:Internal VNet mode: the gateway has only a private VIP. public_network_access can't be disabled at creation; nothing is exposed publicly.
  name                 = var.name
  location             = var.location
  resource_group_name  = var.resource_group_name
  publisher_name       = var.publisher_name
  publisher_email      = var.publisher_email
  sku_name             = var.sku_name
  zones                = local.is_premium ? var.zones : null
  virtual_network_type = "Internal"
  min_api_version      = "2021-08-01" # blocks older, less secure management API versions
  tags                 = var.tags

  virtual_network_configuration {
    subnet_id = var.subnet_id
  }

  identity {
    type = "SystemAssigned"
  }

  protocols {
    http2_enabled = true
  }

  security {
    frontend_ssl30_enabled = false
    frontend_tls10_enabled = false
    frontend_tls11_enabled = false
    backend_ssl30_enabled  = false
    backend_tls10_enabled  = false
    backend_tls11_enabled  = false
  }

  sign_up {
    enabled = false # no developer portal self-service; callers are managed identities
    terms_of_service {
      consent_required = false
      enabled          = false
    }
  }
}

# ---- DNS: internal mode has no Azure DNS record, so publish <name>.azure-api.net privately.
# A zone named exactly after this gateway (not a shared azure-api.net zone) means one client's
# record can never shadow another's. In landing-zone mode P&T links this zone to the hub resolver.
resource "azurerm_private_dns_zone" "gateway" {
  name                = "${var.name}.azure-api.net"
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_a_record" "gateway" {
  name                = "@"
  zone_name           = azurerm_private_dns_zone.gateway.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = azurerm_api_management.this.private_ip_addresses
}

resource "azurerm_private_dns_zone_virtual_network_link" "gateway" {
  name                  = "link-spoke"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.gateway.name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

# ---- Model access: the gateway, not the app, holds "OpenAI User" on each backend account.
resource "azurerm_role_assignment" "gateway_to_openai" {
  for_each             = { for b in var.backends : b.name => b.resource_id }
  scope                = each.value
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = azurerm_api_management.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_api_management_backend" "openai" {
  #checkov:skip=CKV_AZURE_215:URL is always https (an Azure AI endpoint, interpolated so Checkov cannot read it); protocol "http" means HTTP-based rather than SOAP. TLS chain and name validation are on.
  for_each            = { for b in var.backends : b.name => b }
  name                = each.key
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  protocol            = "http"
  url                 = "${trimsuffix(each.value.url, "/")}/openai"
  description         = "Azure OpenAI backend ${each.key}"

  tls {
    validate_certificate_chain = true
    validate_certificate_name  = true
  }

  # Trip after repeated throttling or server errors; honour Retry-After so a PTU backend that is
  # briefly saturated recovers without being hammered.
  circuit_breaker_rule {
    name                       = "openai-breaker"
    trip_duration              = "PT1M"
    accept_retry_after_enabled = true

    failure_condition {
      count             = 3
      interval_duration = "PT1M"
      error_reasons     = ["Server errors"]

      status_code_range {
        min = 429
        max = 429
      }

      status_code_range {
        min = 500
        max = 599
      }
    }
  }
}

# ---- Optional content safety (Prompt Shields) backend.
resource "azurerm_cognitive_account" "content_safety" {
  #checkov:skip=CKV2_AZURE_22:Microsoft-managed keys, same as the client's AOAI account (CMK is a per-client contract option).
  count                         = var.enable_content_safety ? 1 : 0
  name                          = var.content_safety_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  kind                          = "ContentSafety"
  sku_name                      = "S0"
  custom_subdomain_name         = var.content_safety_name
  public_network_access_enabled = false
  local_auth_enabled            = false
  tags                          = var.tags

  identity {
    type = "SystemAssigned"
  }

  network_acls {
    default_action = "Deny"
  }
}

resource "azurerm_private_endpoint" "content_safety" {
  count               = var.enable_content_safety ? 1 : 0
  name                = "pe-${var.content_safety_name}"
  location            = var.location
  resource_group_name = var.resource_group_name
  subnet_id           = var.pe_subnet_id
  tags                = var.tags

  private_service_connection {
    name                           = "pe-${var.content_safety_name}-psc"
    private_connection_resource_id = azurerm_cognitive_account.content_safety[0].id
    subresource_names              = ["account"]
    is_manual_connection           = false
  }

  dynamic "private_dns_zone_group" {
    for_each = length(var.cognitiveservices_private_dns_zone_ids) > 0 ? [1] : []
    content {
      name                 = "default"
      private_dns_zone_ids = var.cognitiveservices_private_dns_zone_ids
    }
  }

  lifecycle {
    ignore_changes = [private_dns_zone_group]
  }
}

resource "azurerm_role_assignment" "gateway_to_content_safety" {
  count                = var.enable_content_safety ? 1 : 0
  scope                = azurerm_cognitive_account.content_safety[0].id
  role_definition_name = "Cognitive Services User"
  principal_id         = azurerm_api_management.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_api_management_backend" "content_safety" {
  #checkov:skip=CKV_AZURE_215:URL is always https (an Azure AI endpoint, interpolated so Checkov cannot read it); protocol "http" means HTTP-based rather than SOAP. TLS chain and name validation are on.
  count               = var.enable_content_safety ? 1 : 0
  name                = "content-safety"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  protocol            = "http"
  url                 = trimsuffix(azurerm_cognitive_account.content_safety[0].endpoint, "/")

  tls {
    validate_certificate_chain = true
    validate_certificate_name  = true
  }
}

# ---- The Azure OpenAI API surface. Apps keep using the standard SDK; only the endpoint changes.
resource "azurerm_api_management_api" "openai" {
  name                  = "azure-openai"
  resource_group_name   = var.resource_group_name
  api_management_name   = azurerm_api_management.this.name
  revision              = "1"
  display_name          = "Azure OpenAI (${var.client})"
  path                  = "openai"
  protocols             = ["https"]
  subscription_required = false # callers authenticate with Entra tokens, see policy

  import {
    content_format = "openapi+json-link"
    content_value  = "https://raw.githubusercontent.com/Azure/azure-rest-api-specs/main/specification/cognitiveservices/data-plane/AzureOpenAI/inference/stable/2024-10-21/inference.json"
  }
}

resource "azurerm_api_management_api_policy" "openai" {
  api_name            = azurerm_api_management_api.openai.name
  api_management_name = azurerm_api_management.this.name
  resource_group_name = var.resource_group_name
  xml_content         = local.policy_xml

  depends_on = [azurerm_api_management_backend.openai, azurerm_api_management_backend.content_safety]
}

# ---- Observability: everything lands in the client's own workspace (ADR 0009).
resource "azurerm_role_assignment" "gateway_to_appinsights" {
  scope                = var.app_insights_id
  role_definition_name = "Monitoring Metrics Publisher" # App Insights has local auth disabled
  principal_id         = azurerm_api_management.this.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_api_management_logger" "appinsights" {
  name                = "client-appinsights"
  resource_group_name = var.resource_group_name
  api_management_name = azurerm_api_management.this.name
  resource_id         = var.app_insights_id

  application_insights {
    connection_string = var.app_insights_connection_string
  }

  depends_on = [azurerm_role_assignment.gateway_to_appinsights]
}

resource "azurerm_api_management_api_diagnostic" "appinsights" {
  identifier               = "applicationinsights"
  resource_group_name      = var.resource_group_name
  api_management_name      = azurerm_api_management.this.name
  api_name                 = azurerm_api_management_api.openai.name
  api_management_logger_id = azurerm_api_management_logger.appinsights.id
  sampling_percentage      = 100
  always_log_errors        = true
  log_client_ip            = true
  verbosity                = "information"

  frontend_request {
    body_bytes     = var.log_request_bodies_bytes
    headers_to_log = ["x-ms-client-request-id"]
  }

  frontend_response {
    body_bytes     = var.log_request_bodies_bytes
    headers_to_log = ["x-ratelimit-remaining-tokens", "x-tokens-consumed"]
  }
}

# Gateway + LLM logs (prompt/completion token counts per request, in ApiManagementGatewayLlmLog)
# in resource-specific tables, for chargeback queries without logging prompt text.
resource "azurerm_monitor_diagnostic_setting" "gateway" {
  name                           = "diag-to-client-law"
  target_resource_id             = azurerm_api_management.this.id
  log_analytics_workspace_id     = var.log_analytics_workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }
}
