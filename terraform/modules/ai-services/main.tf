resource "azurerm_cognitive_account" "openai" {
  name                               = var.openai_name
  location                           = var.location
  resource_group_name                = var.resource_group_name
  kind                               = "OpenAI"
  sku_name                           = "S0"
  custom_subdomain_name              = var.openai_name # required for Entra ID auth and private endpoints
  public_network_access_enabled      = false
  local_auth_enabled                 = false # no API keys (ADR 0004)
  outbound_network_access_restricted = true
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
  public_network_access_enabled = false
  local_authentication_enabled  = false
  tags                          = var.tags

  identity {
    type = "SystemAssigned"
  }
}
