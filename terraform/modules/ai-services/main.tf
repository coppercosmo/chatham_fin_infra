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

resource "azurerm_cognitive_deployment" "this" {
  for_each               = var.model_deployments
  name                   = each.key
  cognitive_account_id   = azurerm_cognitive_account.openai.id
  version_upgrade_option = "NoAutoUpgrade" # model upgrades roll out by ring (ADR 0008)

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
