# Tier 2: one client's data, keys, models and identities, in its own resource group in a shared cell.
# Same modules as a Tier 1 stamp; what's missing is everything the cell shares (network, gateway, compute).

data "azurerm_client_config" "current" {}

module "naming" {
  source      = "../../modules/naming"
  client      = var.client
  environment = var.environment
  location    = var.location
  unique_seed = "${var.subscription_id}/${var.client}" # many clients share one subscription
}

locals {
  n          = module.naming.names
  standalone = length(var.cell.private_dns_zone_ids) > 0
  tags = merge(var.tags, {
    client              = var.client
    cell                = var.cell.name
    isolation_tier      = "2-shared-cell"
    environment         = var.environment
    data_classification = var.data_classification
    cost_center         = var.cost_center
    owner               = var.owner_email
    managed_by          = "terraform"
    stamp               = "ai-advisory-cell-client"
  })
}

# Created by the cell (onboarding step 1, cell var.client_slots), which also gave this run's identity its
# rights here. This root can't create resource groups: its identity has no rights at subscription scope.
data "azurerm_resource_group" "this" {
  name = local.n.resource_group
}

module "key_vault" {
  source              = "../../modules/key-vault"
  name                = local.n.key_vault
  resource_group_name = data.azurerm_resource_group.this.name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = local.tags
}

module "storage" {
  source              = "../../modules/storage"
  name                = local.n.storage_account
  resource_group_name = data.azurerm_resource_group.this.name
  location            = var.location
  tags                = local.tags
}

# The client's own Azure OpenAI account. Its deployments' capacity comes out of the cell subscription's
# regional quota, but capacity on a deployment is a hard partition: no other client can use it.
module "ai" {
  source              = "../../modules/ai-services"
  openai_name         = local.n.openai
  search_name         = local.n.search # unused: search is the cell's, with an index per client
  resource_group_name = data.azurerm_resource_group.this.name
  location            = var.location
  model_deployments   = var.model_deployments
  enable_search       = false
  allowed_outbound_fqdns = [
    trimsuffix(trimprefix(module.storage.blob_endpoint, "https://"), "/"),
  ]
  tags = local.tags
}

module "private_endpoint" {
  source = "../../modules/private-endpoint"
  for_each = {
    kv   = { target = module.key_vault.id, subresource = "vault", zone = "vault" }
    blob = { target = module.storage.id, subresource = "blob", zone = "blob" }
    oai  = { target = module.ai.openai_id, subresource = "account", zone = "openai" }
  }
  name                 = "pe-${module.naming.base}-${each.key}"
  resource_group_name  = data.azurerm_resource_group.this.name
  location             = var.location
  subnet_id            = var.cell.pe_subnet_id # the cell's endpoint subnet; the endpoint itself is ours
  target_resource_id   = each.value.target
  subresource_name     = each.value.subresource
  private_dns_zone_ids = local.standalone ? [var.cell.private_dns_zone_ids[each.value.zone]] : []
  tags                 = local.tags
}

module "observability" {
  source              = "../../modules/observability"
  law_name            = local.n.log_analytics
  appi_name           = local.n.app_insights
  resource_group_name = data.azurerm_resource_group.this.name
  location            = var.location
  retention_in_days   = var.log_retention_days
  tags                = local.tags

  diagnostic_targets = {
    key_vault = module.key_vault.id
    openai    = module.ai.openai_id
    blob      = "${module.storage.id}/blobServices/default"
  }
}

# ------------------------------------------------------------------ identities (the isolation boundary)
# The app runs in the cell's shared environment AS this identity. Its roles reach only this client's data.
module "app_identity" {
  source              = "../../modules/workload-identity"
  name                = local.n.identity_app
  resource_group_name = data.azurerm_resource_group.this.name
  location            = var.location
  tags                = local.tags

  role_assignments = merge(
    {
      kv      = { scope = module.key_vault.id, role = "Key Vault Secrets User" }
      blob    = { scope = module.storage.id, role = "Storage Blob Data Contributor" }
      metrics = { scope = module.observability.app_insights_id, role = "Monitoring Metrics Publisher" }
    },
    var.acr != null ? { acr = { scope = var.acr.id, role = "AcrPull" } } : {},
  )
}

# The shared AI gateway calls THIS client's model account as this identity, and nothing else trusts it.
# The app identity has no model role, so every model call goes through the gateway's limits and metering.
module "gateway_identity" {
  source              = "../../modules/workload-identity"
  name                = "id-${module.naming.base}-gw"
  resource_group_name = data.azurerm_resource_group.this.name
  location            = var.location
  tags                = local.tags

  role_assignments = {
    openai = { scope = module.ai.openai_id, role = "Cognitive Services OpenAI User" }
  }
}

# The cell's pipeline attaches these identities to the client's app and to the shared gateway.
# Managed Identity Operator lets it assign them; it grants no access to anything they can reach.
resource "azurerm_role_assignment" "cell_attaches_identity" {
  for_each = var.cell.deployer_principal_id == null ? {} : {
    app     = module.app_identity.id
    gateway = module.gateway_identity.id
  }
  scope                = each.value
  role_definition_name = "Managed Identity Operator"
  principal_id         = var.cell.deployer_principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "readers" {
  count                = var.reader_group_object_id == null ? 0 : 1
  scope                = data.azurerm_resource_group.this.id
  role_definition_name = "Reader"
  principal_id         = var.reader_group_object_id
  principal_type       = "Group"
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

resource "azurerm_consumption_budget_resource_group" "this" {
  count             = length(var.budget_contact_emails) > 0 ? 1 : 0
  name              = local.n.budget
  resource_group_id = data.azurerm_resource_group.this.id
  amount            = var.monthly_budget_usd
  time_grain        = "Monthly"

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
}
