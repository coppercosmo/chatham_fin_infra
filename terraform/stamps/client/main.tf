# Client stamp: one complete, isolated client environment in its own subscription.
# Everything in here is per client; nothing in here is shared with another client.

data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

module "naming" {
  source      = "../../modules/naming"
  client      = var.client
  environment = var.environment
  location    = var.location
  unique_seed = var.subscription_id
}

locals {
  n          = module.naming.names
  standalone = var.connectivity_mode == "standalone"

  tags = merge(var.tags, {
    client              = var.client
    environment         = var.environment
    data_classification = var.data_classification
    cost_center         = var.cost_center
    owner               = var.owner_email
    managed_by          = "terraform"
    stamp               = "ai-advisory-client"
  })

  # privatelink zones per sub-resource. Only created in standalone mode; in landing_zone mode they
  # live in the P&T hub and DNS records are written by policy.
  private_dns_zones = {
    vault  = "privatelink.vaultcore.azure.net"
    openai = "privatelink.openai.azure.com"
    blob   = "privatelink.blob.core.windows.net"
    search = "privatelink.search.windows.net"
  }
}

resource "azurerm_resource_group" "this" {
  name     = local.n.resource_group
  location = var.location
  tags     = local.tags
}

# ------------------------------------------------------------------ network
module "network" {
  source              = "../../modules/spoke-network"
  name                = local.n.vnet
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  address_space       = var.address_space
  nsg_apps_name       = local.n.nsg_apps
  nsg_pe_name         = local.n.nsg_pe
  route_table_name    = local.n.route_table
  hub                 = var.connectivity_mode == "landing_zone" ? var.hub : null
  tags                = local.tags
}

resource "azurerm_private_dns_zone" "this" {
  for_each            = local.standalone ? local.private_dns_zones : {}
  name                = each.value
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each              = azurerm_private_dns_zone.this
  name                  = "link-${module.network.vnet_name}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = module.network.vnet_id
  registration_enabled  = false
  tags                  = local.tags
}

# ------------------------------------------------------------------ data + AI services
module "key_vault" {
  source              = "../../modules/key-vault"
  name                = local.n.key_vault
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = local.tags
}

module "storage" {
  source              = "../../modules/storage"
  name                = local.n.storage_account
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = local.tags
}

module "ai" {
  source               = "../../modules/ai-services"
  openai_name          = local.n.openai
  search_name          = local.n.search
  resource_group_name  = azurerm_resource_group.this.name
  location             = var.location
  model_deployments    = var.model_deployments
  enable_search        = var.enable_search
  search_replica_count = var.search_replica_count
  allowed_outbound_fqdns = [
    trimsuffix(trimprefix(module.storage.blob_endpoint, "https://"), "/"),
  ]
  tags = local.tags
}

# ------------------------------------------------------------------ private endpoints
locals {
  private_endpoints = merge(
    {
      kv   = { target = module.key_vault.id, subresource = "vault", zone = "vault" }
      blob = { target = module.storage.id, subresource = "blob", zone = "blob" }
      oai  = { target = module.ai.openai_id, subresource = "account", zone = "openai" }
    },
    var.enable_search ? {
      srch = { target = module.ai.search_id, subresource = "searchService", zone = "search" }
    } : {}
  )
}

module "private_endpoint" {
  source               = "../../modules/private-endpoint"
  for_each             = local.private_endpoints
  name                 = "pe-${module.naming.base}-${each.key}"
  resource_group_name  = azurerm_resource_group.this.name
  location             = var.location
  subnet_id            = module.network.pe_subnet_id
  target_resource_id   = each.value.target
  subresource_name     = each.value.subresource
  private_dns_zone_ids = local.standalone ? [azurerm_private_dns_zone.this[each.value.zone].id] : []
  tags                 = local.tags
}

# ------------------------------------------------------------------ observability
module "observability" {
  source              = "../../modules/observability"
  law_name            = local.n.log_analytics
  appi_name           = local.n.app_insights
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  retention_in_days   = var.log_retention_days
  tags                = local.tags

  diagnostic_targets = merge(
    {
      key_vault = module.key_vault.id
      openai    = module.ai.openai_id
      blob      = "${module.storage.id}/blobServices/default"
    },
    var.enable_search ? { search = module.ai.search_id } : {}
  )
}

# ------------------------------------------------------------------ identity
module "app_identity" {
  source              = "../../modules/workload-identity"
  name                = local.n.identity_app
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = local.tags

  role_assignments = merge(
    {
      openai  = { scope = module.ai.openai_id, role = "Cognitive Services OpenAI User" }
      kv      = { scope = module.key_vault.id, role = "Key Vault Secrets User" }
      blob    = { scope = module.storage.id, role = "Storage Blob Data Contributor" }
      metrics = { scope = module.observability.app_insights_id, role = "Monitoring Metrics Publisher" }
    },
    var.enable_search ? {
      search = { scope = module.ai.search_id, role = "Search Index Data Reader" }
    } : {},
    var.acr != null ? {
      acr = { scope = var.acr.id, role = "AcrPull" }
    } : {}
  )
}

# AI Search reads documents from blob storage and calls AOAI for vectorization with its own identity.
resource "azurerm_role_assignment" "search_to_blob" {
  count                = var.enable_search ? 1 : 0
  scope                = module.storage.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = module.ai.search_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "search_to_openai" {
  count                = var.enable_search ? 1 : 0
  scope                = module.ai.openai_id
  role_definition_name = "Cognitive Services OpenAI User"
  principal_id         = module.ai.search_principal_id
  principal_type       = "ServicePrincipal"
}

# Standing read access for the P&T-owned client reader group. Write access is PIM-only.
resource "azurerm_role_assignment" "readers" {
  count                = var.reader_group_object_id == null ? 0 : 1
  scope                = azurerm_resource_group.this.id
  role_definition_name = "Reader"
  principal_id         = var.reader_group_object_id
  principal_type       = "Group"
}

# ------------------------------------------------------------------ compute
module "apps" {
  source                             = "../../modules/container-apps"
  environment_name                   = local.n.container_app_environment
  infrastructure_resource_group_name = local.n.container_app_infra_rg
  app_name                           = local.n.container_app_api
  resource_group_name                = azurerm_resource_group.this.name
  location                           = var.location
  infrastructure_subnet_id           = module.network.apps_subnet_id
  vnet_id                            = module.network.vnet_id
  log_analytics_workspace_id         = module.observability.workspace_id
  zone_redundant                     = var.zone_redundant
  identity_id                        = module.app_identity.id
  identity_client_id                 = module.app_identity.client_id
  image                              = var.app_image
  registry_server                    = var.acr == null ? null : var.acr.login_server
  app_insights_connection_string     = module.observability.app_insights_connection_string
  tags                               = local.tags

  env = merge(
    {
      CLIENT_CODE            = var.client
      AZURE_OPENAI_ENDPOINT  = module.ai.openai_endpoint
      AZURE_KEY_VAULT_URI    = module.key_vault.uri
      AZURE_STORAGE_BLOB_URL = module.storage.blob_endpoint
    },
    var.enable_search ? { AZURE_SEARCH_ENDPOINT = module.ai.search_endpoint } : {}
  )

  depends_on = [module.app_identity, module.private_endpoint]
}

# ------------------------------------------------------------------ guardrails we own
resource "azurerm_management_lock" "data" {
  for_each = var.enable_locks ? {
    key_vault = module.key_vault.id
    storage   = module.storage.id
    openai    = module.ai.openai_id
  } : {}
  name       = "lock-cannot-delete"
  scope      = each.value
  lock_level = "CanNotDelete"
  notes      = "Client data. Remove via enable_locks=false during offboarding only."
}

resource "azurerm_consumption_budget_subscription" "this" {
  count           = length(var.budget_contact_emails) > 0 ? 1 : 0
  name            = local.n.budget
  subscription_id = data.azurerm_subscription.current.id
  amount          = var.monthly_budget_usd
  time_grain      = "Monthly"

  time_period {
    start_date = "2026-12-01T00:00:00Z"
  }

  notification {
    enabled        = true
    threshold      = 80
    operator       = "GreaterThan"
    threshold_type = "Actual"
    contact_emails = var.budget_contact_emails
  }

  notification {
    enabled        = true
    threshold      = 100
    operator       = "GreaterThan"
    threshold_type = "Forecasted"
    contact_emails = var.budget_contact_emails
  }
}
