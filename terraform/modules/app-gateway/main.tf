# Per-client Application Gateway WAF_v2: the only way into a client's environment (ADR 0010).
#
#   client users --TLS--> [App Gateway WAF_v2, snet-agw] --TLS--> [Container Apps internal env | AKS internal NGINX]
#                              |                                     (re-encrypted: end-to-end TLS)
#                              +-- listener cert from the client's Key Vault, read with a managed identity
#                              +-- WAF policy: DRS 2.1 + Bot Manager, prompt-field exclusions, rate limit
#                              +-- access + firewall logs to the client's Log Analytics

locals {
  public          = var.frontend_mode == "public"
  listener_fe     = local.public ? "public" : "private"
  backend_is_fqdn = var.backend_fqdn != null
}

# ---------------------------------------------------------------- identity for Key Vault
resource "azurerm_user_assigned_identity" "agw" {
  name                = var.identity_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_role_assignment" "agw_kv" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User" # certificates are read through their secret
  principal_id         = azurerm_user_assigned_identity.agw.principal_id
  principal_type       = "ServicePrincipal"
}

# ---------------------------------------------------------------- WAF policy
resource "azurerm_web_application_firewall_policy" "this" {
  #checkov:skip=CKV_AZURE_135:Checkov looks for the legacy OWASP rule set. Microsoft_DefaultRuleSet 2.1 includes the Log4j (CVE-2021-44228) rules.
  name                = var.waf_policy_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags

  policy_settings {
    enabled                          = true
    mode                             = var.waf_mode
    request_body_check               = true
    request_body_inspect_limit_in_kb = 128
    max_request_body_size_in_kb      = var.waf_max_request_body_kb
    file_upload_limit_in_mb          = var.waf_file_upload_limit_mb
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

    # Narrow exclusions: only the prompt fields, only the SQLI and XSS groups.
    dynamic "exclusion" {
      for_each = var.waf_prompt_field_exclusions
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
    for_each = length(var.allowed_client_cidrs) > 0 ? [1] : []
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
        match_values       = var.allowed_client_cidrs
      }
    }
  }

  custom_rules {
    name                 = "RateLimitPerClientIp"
    priority             = 10
    rule_type            = "RateLimitRule"
    action               = "Block"
    rate_limit_duration  = "OneMin"
    rate_limit_threshold = var.rate_limit_per_minute
    group_rate_limit_by  = "ClientAddr"

    match_conditions {
      match_variables {
        variable_name = "RemoteAddr"
      }
      operator           = "IPMatch"
      negation_condition = true
      match_values       = ["255.255.255.255/32"] # i.e. "every request"
    }
  }
}

# ---------------------------------------------------------------- public frontend (public mode only)
resource "azurerm_public_ip" "this" {
  count               = local.public ? 1 : 0
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
  firewall_policy_id                = azurerm_web_application_firewall_policy.this.id
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

  # Stream LLM tokens back as they are generated (server-sent events) instead of buffering the
  # whole response. Requests stay buffered so the WAF can inspect the full body.
  global {
    request_buffering_enabled  = true
    response_buffering_enabled = false
  }

  gateway_ip_configuration {
    name      = "gateway"
    subnet_id = var.subnet_id
  }

  frontend_ip_configuration {
    name                          = "private"
    subnet_id                     = var.subnet_id
    private_ip_address            = var.private_ip_address
    private_ip_address_allocation = "Static"
  }

  dynamic "frontend_ip_configuration" {
    for_each = local.public ? [1] : []
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
    policy_name = "AppGwSslPolicy20220101S" # TLS 1.2+ with strong ciphers only
  }

  ssl_certificate {
    name                = "listener"
    key_vault_secret_id = var.certificate_secret_id
  }

  http_listener {
    name                           = "https"
    frontend_ip_configuration_name = local.listener_fe
    frontend_port_name             = "https"
    protocol                       = "Https"
    ssl_certificate_name           = "listener"
    host_name                      = var.host_name
    require_sni                    = true
  }

  backend_address_pool {
    name         = "app"
    fqdns        = local.backend_is_fqdn ? [var.backend_fqdn] : null
    ip_addresses = local.backend_is_fqdn ? null : [var.backend_ip]
  }

  # End-to-end TLS: re-encrypt to the backend. Container Apps and the AKS ingress both present
  # certificates from a public CA, so no custom trusted root is needed.
  backend_http_settings {
    name                                = "app-https"
    port                                = 443
    protocol                            = "Https"
    cookie_based_affinity               = "Disabled"
    request_timeout                     = var.backend_request_timeout_seconds
    host_name                           = var.backend_host_header
    pick_host_name_from_backend_address = var.backend_host_header == null
    probe_name                          = "app-health"
  }

  probe {
    name                                      = "app-health"
    protocol                                  = "Https"
    path                                      = var.health_probe_path
    interval                                  = 30
    timeout                                   = 30
    unhealthy_threshold                       = 3
    pick_host_name_from_backend_http_settings = true

    match {
      status_code = ["200-399"]
    }
  }

  request_routing_rule {
    name                       = "https-to-app"
    rule_type                  = "Basic"
    priority                   = 100
    http_listener_name         = "https"
    backend_address_pool_name  = "app"
    backend_http_settings_name = "app-https"
  }

  lifecycle {
    precondition {
      condition     = (var.backend_fqdn == null) != (var.backend_ip == null)
      error_message = "Set exactly one of backend_fqdn (Container Apps) or backend_ip (AKS)."
    }
  }

  depends_on = [azurerm_role_assignment.agw_kv] # gateway fails to provision if it can't read the cert
}

resource "azurerm_monitor_diagnostic_setting" "agw" {
  name                       = "diag-to-client-law"
  target_resource_id         = azurerm_application_gateway.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "allLogs" # access, performance and firewall logs
  }
}
