locals {
  allowed_outbound_fqdns = concat(
    var.enable_search ? ["${var.search_name}.search.windows.net"] : [],
    var.allowed_outbound_fqdns,
  )
}

resource "azurerm_cognitive_account" "openai" {
  #checkov:skip=CKV2_AZURE_22:Microsoft-managed keys by default. CMK is a per-client contract option (README known gaps); it needs a client-scoped Key Vault key and identity, not a platform-wide default.
  name                          = var.openai_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  kind                          = "OpenAI"
  sku_name                      = "S0"
  custom_subdomain_name         = var.openai_name # required for Entra ID auth and private endpoints
  public_network_access_enabled = false
  local_auth_enabled            = false # no API keys (ADR 0004)
  # Data-exfiltration guard: the account may only call out to this client's own endpoints
  # (e.g. its AI Search and blob storage for "on your data"), never anywhere else.
  outbound_network_access_restricted = true
  fqdns                              = local.allowed_outbound_fqdns
  tags                               = var.tags

  identity {
    type = "SystemAssigned"
  }

  network_acls {
    default_action = "Deny"
  }
}

# Content filter (RAI policy) for every deployment in this account (ADR 0006, ADR 0015). Starts from Microsoft's
# defaults and adds what a RAG app needs most: indirect attack detection, which looks for instructions hidden in
# retrieved documents. It is off in Microsoft's default policy. It only inspects text the app marks as documents
# (""" <documents> ... </documents> """, JSON-escaped), so the app wraps every retrieved chunk that way.
locals {
  harm_categories = ["Hate", "Sexual", "Selfharm", "Violence"]
  content_filters = concat(
    [
      for pair in setproduct(local.harm_categories, ["Prompt", "Completion"]) : {
        name     = pair[0]
        source   = pair[1]
        enabled  = true
        blocking = true
        severity = var.content_filter.severity_threshold
      }
    ],
    [
      # These have no severity; the provider requires a value, which Azure ignores.
      { name = "Jailbreak", source = "Prompt", enabled = true, blocking = true, severity = "High" },
      { name = "Indirect Attack", source = "Prompt", enabled = var.content_filter.indirect_attack_detection, blocking = var.content_filter.indirect_attack_detection, severity = "High" },
      { name = "Protected Material Text", source = "Completion", enabled = true, blocking = true, severity = "High" },
      { name = "Protected Material Code", source = "Completion", enabled = true, blocking = true, severity = "High" },
    ],
  )
}

resource "azurerm_cognitive_account_rai_policy" "this" {
  name                 = var.content_filter.name
  cognitive_account_id = azurerm_cognitive_account.openai.id
  base_policy_name     = "Microsoft.Default"
  tags                 = var.tags

  dynamic "content_filter" {
    for_each = local.content_filters
    content {
      name               = content_filter.value.name
      source             = content_filter.value.source
      filter_enabled     = content_filter.value.enabled
      block_enabled      = content_filter.value.blocking
      severity_threshold = content_filter.value.severity
    }
  }
}

resource "azurerm_cognitive_deployment" "this" {
  for_each               = var.model_deployments
  name                   = each.key
  cognitive_account_id   = azurerm_cognitive_account.openai.id
  version_upgrade_option = "NoAutoUpgrade" # model upgrades roll out by ring (ADR 0008)
  rai_policy_name        = azurerm_cognitive_account_rai_policy.this.name

  model {
    format  = "OpenAI"
    name    = each.value.model_name
    version = each.value.model_version
  }

  sku {
    name     = each.value.sku
    capacity = each.value.capacity
  }
}

resource "azurerm_search_service" "this" {
  #checkov:skip=CKV_AZURE_208:Replica count is a per-stamp cost choice (search_replica_count): 2 gives the query SLA, 3 adds the index-update SLA. Ingestion is batch and retries.
  count                         = var.enable_search ? 1 : 0
  name                          = var.search_name
  location                      = var.location
  resource_group_name           = var.resource_group_name
  sku                           = var.search_sku
  replica_count                 = var.search_replica_count # >= 2 read SLA, >= 3 read/write SLA
  partition_count               = 1
  public_network_access_enabled = false
  local_authentication_enabled  = false
  tags                          = var.tags

  identity {
    type = "SystemAssigned"
  }
}
