# Shared, multi-site Application Gateway WAF_v2 for a Tier 2 cell (ADR 0014).
#
# One gateway, one frontend IP, one listener per client host name. Isolation between clients at the edge
# comes from three things, all per site:
#   - the host name (SNI required): it decides which client's app a request reaches,
#   - its own WAF policy: allow-list, rate limit, rule tuning and mode never leak across clients,
#   - its own certificate.
# Behind it, each client's app accepts traffic only from this subnet and only that client's users can sign in.
# Clients that need separation by network address (their own frontend IP, their own firewall rule) use Tier 1.

locals {
  public_sites     = { for k, s in var.sites : k => s if s.frontend == "public" }
  create_public_ip = length(local.public_sites) > 0 || var.enable_private_link
}

resource "azurerm_user_assigned_identity" "agw" {
  name                = var.identity_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "agw_kv" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_user_assigned_identity.agw.principal_id
  principal_type       = "ServicePrincipal"
}

# ---------------------------------------------------------------- WAF policies
# Baseline policy on the gateway itself; each listener overrides it with its client's policy.
resource "azurerm_web_application_firewall_policy" "baseline" {
  #checkov:skip=CKV_AZURE_135:Microsoft_DefaultRuleSet 2.1 includes the Log4j rules; Checkov looks for the legacy OWASP set.
  name                = "waf-${var.name}-baseline"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  policy_settings {
    enabled                          = true
    mode                             = "Prevention"
    request_body_check               = true
    request_body_inspect_limit_in_kb = 128
  }

  managed_rules {
    managed_rule_set {
      type    = "Microsoft_DefaultRuleSet"
      version = "2.1"
    }
    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.1"
    }
  }
}

resource "azurerm_web_application_firewall_policy" "site" {
  #checkov:skip=CKV_AZURE_135:Microsoft_DefaultRuleSet 2.1 includes the Log4j rules; Checkov looks for the legacy OWASP set.
  for_each            = var.sites
  name                = "waf-${var.name}-${each.key}"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = merge(var.tags, { client = each.key })

  policy_settings {
    enabled                          = true
    mode                             = each.value.waf_mode
    request_body_check               = true
    request_body_inspect_limit_in_kb = 128
    max_request_body_size_in_kb      = 2000
    file_upload_limit_in_mb          = 100
  }

  managed_rules {
    managed_rule_set {
      type    = "Microsoft_DefaultRuleSet"
      version = "2.1"
    }

    managed_rule_set {
      type    = "Microsoft_BotManagerRuleSet"
      version = "1.1"
    }

    dynamic "exclusion" {
      for_each = each.value.waf_prompt_field_exclusions
      content {
        match_variable          = "RequestArgNames"
        selector_match_operator = "Equals"
        selector                = exclusion.value

        excluded_rule_set {
          type    = "Microsoft_DefaultRuleSet"
          version = "2.1"
          rule_group {
            rule_group_name = "SQLI"
          }
          rule_group {
            rule_group_name = "XSS"
          }
        }
      }
    }
  }

  dynamic "custom_rules" {
    for_each = length(each.value.allowed_client_cidrs) > 0 ? [1] : []
    content {
      name      = "BlockOutsideClientRanges"
      priority  = 5
      rule_type = "MatchRule"
      action    = "Block"

      match_conditions {
        match_variables {
          variable_name = "RemoteAddr"
        }
        operator           = "IPMatch"
        negation_condition = true
        match_values       = each.value.allowed_client_cidrs
      }
    }
  }

  custom_rules {
    name                 = "RateLimitPerClientIp"
    priority             = 10
    rule_type            = "RateLimitRule"
    action               = "Block"
    rate_limit_duration  = "OneMin"
    rate_limit_threshold = each.value.rate_limit_per_minute
    group_rate_limit_by  = "ClientAddr"

    match_conditions {
      match_variables {
        variable_name = "RemoteAddr"
      }
      operator           = "IPMatch"
      negation_condition = true
      match_values       = ["255.255.255.255/32"]
    }
  }
}

resource "azurerm_public_ip" "this" {
  count               = local.create_public_ip ? 1 : 0
  name                = var.public_ip_name
  location            = var.location
  resource_group_name = var.resource_group_name
  allocation_method   = "Static"
  sku                 = "Standard"
  zones               = var.zones
  tags                = var.tags
}

# ---------------------------------------------------------------- gateway
resource "azurerm_application_gateway" "this" {
  name                              = var.name
  location                          = var.location
  resource_group_name               = var.resource_group_name
  zones                             = var.zones
  firewall_policy_id                = azurerm_web_application_firewall_policy.baseline.id
  force_firewall_policy_association = true
  tags                              = var.tags

  sku {
    name = "WAF_v2"
    tier = "WAF_v2"
  }

  autoscale_configuration {
    min_capacity = var.autoscale.min_capacity
    max_capacity = var.autoscale.max_capacity
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.agw.id]
  }

  global {
    request_buffering_enabled  = true
    response_buffering_enabled = false # stream LLM tokens
  }

  gateway_ip_configuration {
    name      = "gateway"
    subnet_id = var.subnet_id
  }

  frontend_ip_configuration {
    name                            = "private"
    subnet_id                       = var.subnet_id
    private_ip_address              = var.private_ip_address
    private_ip_address_allocation   = "Static"
    private_link_configuration_name = var.enable_private_link ? "private-link" : null
  }

  dynamic "private_link_configuration" {
    for_each = var.enable_private_link ? [1] : []
    content {
      name = "private-link"
      ip_configuration {
        name                          = "pl-ip-1"
        subnet_id                     = var.private_link_subnet_id
        private_ip_address_allocation = "Dynamic"
        primary                       = true
      }
    }
  }

  dynamic "frontend_ip_configuration" {
    for_each = local.create_public_ip ? [1] : []
    content {
      name                 = "public"
      public_ip_address_id = azurerm_public_ip.this[0].id
    }
  }

  frontend_port {
    name = "https"
    port = 443
  }

  ssl_policy {
    policy_type = "Predefined"
    policy_name = "AppGwSslPolicy20220101S"
  }

  dynamic "ssl_certificate" {
    for_each = var.sites
    content {
      name                = "cert-${ssl_certificate.key}"
      key_vault_secret_id = ssl_certificate.value.certificate_secret_id
    }
  }

  dynamic "http_listener" {
    for_each = var.sites
    content {
      name                           = "https-${http_listener.key}"
      frontend_ip_configuration_name = http_listener.value.frontend
      frontend_port_name             = "https"
      protocol                       = "Https"
      ssl_certificate_name           = "cert-${http_listener.key}"
      host_name                      = http_listener.value.host_name
      require_sni                    = true
      firewall_policy_id             = azurerm_web_application_firewall_policy.site[http_listener.key].id
    }
  }

  # One pool (the environment's static IP) shared by every site; the host header picks the app.
  backend_address_pool {
    name         = "cell-environment"
    ip_addresses = [var.backend_ip]
  }

  dynamic "backend_http_settings" {
    for_each = var.sites
    content {
      name                  = "app-${backend_http_settings.key}"
      port                  = 443
      protocol              = "Https"
      cookie_based_affinity = "Disabled"
      request_timeout       = var.backend_request_timeout_seconds
      host_name             = backend_http_settings.value.backend_host_header
      probe_name            = "health-${backend_http_settings.key}"
    }
  }

  dynamic "probe" {
    for_each = var.sites
    content {
      name                                      = "health-${probe.key}"
      protocol                                  = "Https"
      path                                      = probe.value.health_probe_path
      interval                                  = 30
      timeout                                   = 30
      unhealthy_threshold                       = 3
      pick_host_name_from_backend_http_settings = true
      match {
        status_code = ["200-399"]
      }
    }
  }

  dynamic "request_routing_rule" {
    for_each = { for i, k in sort(keys(var.sites)) : k => 100 + i * 10 }
    content {
      name                       = "route-${request_routing_rule.key}"
      rule_type                  = "Basic"
      priority                   = request_routing_rule.value
      http_listener_name         = "https-${request_routing_rule.key}"
      backend_address_pool_name  = "cell-environment"
      backend_http_settings_name = "app-${request_routing_rule.key}"
    }
  }

  lifecycle {
    precondition {
      condition     = !var.enable_private_link || var.private_link_subnet_id != null
      error_message = "enable_private_link needs private_link_subnet_id."
    }
  }

  depends_on = [azurerm_role_assignment.agw_kv]
}

resource "azurerm_monitor_diagnostic_setting" "agw" {
  name                       = "diag-to-cell-law"
  target_resource_id         = azurerm_application_gateway.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs"
  }
}
