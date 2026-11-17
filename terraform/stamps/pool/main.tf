# Tier 3: pooled (ADR 0014). One app serves every tenant. The rule that makes it safe enough for
# low-sensitivity data: the pooled app's own identity has NO data role. It reads tenant data with the
# signed-in user's token (on-behalf-of), and Azure checks that user's tenant group at container and index
# scope. Background work runs per tenant, as a per-tenant identity. The tenant is only ever taken from a
# validated token claim.

data "azurerm_client_config" "current" {}

module "naming" {
  source      = "../../modules/naming"
  client      = var.pool
  environment = var.environment
  location    = var.location
  unique_seed = var.subscription_id
}

locals {
  n          = module.naming.names
  standalone = var.connectivity_mode == "standalone"
  tags = merge(var.tags, {
    client              = "shared" # required RG tag (policy); per-tenant cost comes from the gateway's Tenant metric
    pool                = var.pool
    isolation_tier      = "3-pooled"
    environment         = var.environment
    data_classification = "internal"
    cost_center         = var.cost_center
    owner               = var.owner_email
    managed_by          = "terraform"
    stamp               = "ai-advisory-pool"
  })
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

module "network" {
  source                = "../../modules/spoke-network"
  name                  = local.n.vnet
  resource_group_name   = azurerm_resource_group.this.name
  location              = var.location
  address_space         = var.address_space
  nsg_apps_name         = local.n.nsg_apps
  nsg_pe_name           = local.n.nsg_pe
  route_table_name      = local.n.route_table
  hub                   = var.connectivity_mode == "landing_zone" ? var.hub : null
  enable_apim_subnet    = true
  nsg_apim_name         = local.n.nsg_apim
  enable_ingress_subnet = true
  nsg_agw_name          = local.n.nsg_agw
  tags                  = local.tags
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

# ------------------------------------------------------------------ shared stores, partitioned per tenant
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
  containers          = [] # one per tenant, below, each with its own encryption scope
  tags                = local.tags
}

module "ai" {
  source               = "../../modules/ai-services"
  openai_name          = local.n.openai
  search_name          = local.n.search
  resource_group_name  = azurerm_resource_group.this.name
  location             = var.location
  model_deployments    = var.model_deployments
  enable_search        = true
  search_sku           = "standard"
  search_replica_count = 2
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
    srch = { target = module.ai.search_id, subresource = "searchService", zone = "search" }
  }
  name                 = "pe-${module.naming.base}-${each.key}"
  resource_group_name  = azurerm_resource_group.this.name
  location             = var.location
  subnet_id            = module.network.pe_subnet_id
  target_resource_id   = each.value.target
  subresource_name     = each.value.subresource
  private_dns_zone_ids = local.standalone ? [azurerm_private_dns_zone.this[each.value.zone].id] : []
  tags                 = local.tags
}

module "observability" {
  source              = "../../modules/observability"
  law_name            = local.n.log_analytics
  appi_name           = local.n.app_insights
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  retention_in_days   = var.log_retention_days
  tags                = local.tags
  diagnostic_targets = {
    key_vault = module.key_vault.id
    openai    = module.ai.openai_id
    blob      = "${module.storage.id}/blobServices/default"
    search    = module.ai.search_id
  }
}

# One encryption scope per tenant, enforced as its container's default with no override. With cmk_key_id the
# scope uses that tenant's key: disabling the key makes the tenant's blobs unreadable (crypto-shredding).
resource "azurerm_storage_encryption_scope" "tenant" {
  for_each                           = var.tenants
  name                               = each.key
  storage_account_id                 = module.storage.id
  source                             = each.value.cmk_key_id == null ? "Microsoft.Storage" : "Microsoft.KeyVault"
  key_vault_key_id                   = each.value.cmk_key_id
  infrastructure_encryption_required = true
}

resource "azurerm_storage_container" "tenant" {
  #checkov:skip=CKV2_AZURE_21:Blob read/write/delete logs go to the pool workspace via observability.diagnostic_targets.blob.
  for_each                          = var.tenants
  name                              = each.key
  storage_account_id                = module.storage.id
  container_access_type             = "private"
  default_encryption_scope          = azurerm_storage_encryption_scope.tenant[each.key].name
  encryption_scope_override_enabled = false
}

locals {
  container_scope = { for k in keys(var.tenants) : k => "${module.storage.id}/blobServices/default/containers/${k}" }
  index_scope     = { for k in keys(var.tenants) : k => "${module.ai.search_id}/indexes/${k}" }
}

# The tenant's group IS the data permission: read on its own container and its own index, nothing else.
resource "azurerm_role_assignment" "tenant_users_blob" {
  for_each             = var.tenants
  scope                = local.container_scope[each.key]
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = each.value.users_group_object_id
  principal_type       = "Group"
  depends_on           = [azurerm_storage_container.tenant]
}

resource "azurerm_role_assignment" "tenant_users_index" {
  for_each             = var.tenants
  scope                = local.index_scope[each.key]
  role_definition_name = "Search Index Data Reader"
  principal_id         = each.value.users_group_object_id
  principal_type       = "Group"
}

# ------------------------------------------------------------------ per-tenant ingestion (no user, so its own identity)
resource "azurerm_user_assigned_identity" "ingest" {
  for_each            = var.tenants
  name                = "id-${module.naming.base}-${each.key}-ingest"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = merge(local.tags, { tenant = each.key })
}

resource "azurerm_role_assignment" "ingest_blob" {
  for_each             = var.tenants
  scope                = local.container_scope[each.key]
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.ingest[each.key].principal_id
  principal_type       = "ServicePrincipal"
  depends_on           = [azurerm_storage_container.tenant]
}

resource "azurerm_role_assignment" "ingest_index" {
  for_each             = var.tenants
  scope                = local.index_scope[each.key]
  role_definition_name = "Search Index Data Contributor"
  principal_id         = azurerm_user_assigned_identity.ingest[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "ingest_acr" {
  for_each             = var.acr == null ? {} : var.tenants
  scope                = var.acr.id
  role_definition_name = "AcrPull"
  principal_id         = azurerm_user_assigned_identity.ingest[each.key].principal_id
  principal_type       = "ServicePrincipal"
}

# The same ingestion job design as Tiers 1 and 2 (modules/ingestion-job, ADR 0015). Each tenant's job runs as that
# tenant's identity, reads its container and writes its index; embeddings go through the pool's gateway, which maps
# the job's identity to its tenant for limits and metering.
module "ingestion" {
  source                       = "../../modules/ingestion-job"
  resource_group_name          = azurerm_resource_group.this.name
  location                     = var.location
  tags                         = local.tags
  container_app_environment_id = module.apps.environment_id
  image                        = var.ingest_image
  registry_server              = var.acr == null ? null : var.acr.login_server

  jobs = {
    for k, t in var.tenants : k => {
      identity_id        = azurerm_user_assigned_identity.ingest[k].id
      identity_client_id = azurerm_user_assigned_identity.ingest[k].client_id
      storage_blob_url   = module.storage.blob_endpoint
      storage_container  = k # a container per tenant
      search_endpoint    = module.ai.search_endpoint
      search_index       = k
      openai_endpoint    = module.ai_gateway.gateway_url
      schedule           = t.ingest_schedule
    }
  }

  # Index definitions on the shared service belong to the pool, not to any tenant identity.
  index_admin = {
    identity_id        = azurerm_user_assigned_identity.index_admin.id
    identity_client_id = azurerm_user_assigned_identity.index_admin.client_id
    search_endpoint    = module.ai.search_endpoint
    indexes            = keys(var.tenants)
  }

  depends_on = [azurerm_role_assignment.ingest_blob, azurerm_role_assignment.ingest_index, azurerm_role_assignment.index_admin]
}

# The per-tenant jobs used to be declared here; moving them into the shared module keeps every existing job.
moved {
  from = azurerm_container_app_job.ingest
  to   = module.ingestion.azurerm_container_app_job.this
}

# Search Service Contributor manages index definitions but can't read or load documents. It is service-wide, so
# it belongs to this platform identity and never to a tenant's.
resource "azurerm_user_assigned_identity" "index_admin" {
  name                = "id-${module.naming.base}-index-admin"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = local.tags
}

resource "azurerm_role_assignment" "index_admin" {
  for_each = merge(
    { search = { scope = module.ai.search_id, role = "Search Service Contributor" } },
    var.acr == null ? {} : { acr = { scope = var.acr.id, role = "AcrPull" } },
  )
  scope                = each.value.scope
  role_definition_name = each.value.role
  principal_id         = azurerm_user_assigned_identity.index_admin.principal_id
  principal_type       = "ServicePrincipal"
}

# ------------------------------------------------------------------ the pooled app
# Its identity pulls images and publishes telemetry. No storage, search, vault or model role.
module "app_identity" {
  source              = "../../modules/workload-identity"
  name                = local.n.identity_app
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tags                = local.tags
  role_assignments = merge(
    { metrics = { scope = module.observability.app_insights_id, role = "Monitoring Metrics Publisher" } },
    var.acr != null ? { acr = { scope = var.acr.id, role = "AcrPull" } } : {},
  )
}

module "apps" {
  source                             = "../../modules/container-apps"
  environment_name                   = local.n.container_app_environment
  infrastructure_resource_group_name = local.n.container_app_infra_rg
  app_name                           = local.n.container_app_api
  resource_group_name                = azurerm_resource_group.this.name
  location                           = var.location
  infrastructure_subnet_id           = module.network.workload_subnet_id
  vnet_id                            = module.network.vnet_id
  log_analytics_workspace_id         = module.observability.workspace_id
  zone_redundant                     = var.zone_redundant
  identity_id                        = module.app_identity.id
  identity_client_id                 = module.app_identity.client_id
  image                              = var.app_image
  registry_server                    = var.acr == null ? null : var.acr.login_server
  app_insights_connection_string     = module.observability.app_insights_connection_string
  min_replicas                       = var.app_min_replicas
  env = {
    TENANCY_MODE           = "pooled" # same image as Tiers 1 and 2; tenant from the token's role claim
    TENANT_ROLE_PREFIX     = var.tenant_role_prefix
    APP_API_AUDIENCE       = var.app_api_audience
    AZURE_OPENAI_ENDPOINT  = module.ai_gateway.gateway_url
    AZURE_STORAGE_BLOB_URL = module.storage.blob_endpoint
    AZURE_SEARCH_ENDPOINT  = module.ai.search_endpoint
    DATA_ACCESS            = "on-behalf-of" # the app reads tenant data with the user's token, never its own
  }
  tags = local.tags

  depends_on = [module.private_endpoint]
}

# ------------------------------------------------------------------ AI gateway in pooled mode
module "ai_gateway" {
  source              = "../../modules/ai-gateway"
  name                = local.n.ai_gateway
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  client              = var.pool
  sku_name            = var.ai_gateway_sku
  zones               = var.zone_redundant ? ["1", "2", "3"] : null
  publisher_email     = var.owner_email
  subnet_id           = module.network.apim_subnet_id
  vnet_id             = module.network.vnet_id
  tags                = local.tags

  backends = [{ name = "aoai-primary", url = module.ai.openai_endpoint, resource_id = module.ai.openai_id }]

  audiences                 = [var.app_api_audience, "https://cognitiveservices.azure.com"]
  allowed_caller_client_ids = concat(var.user_token_client_app_ids, [for i in values(azurerm_user_assigned_identity.ingest) : i.client_id])
  tenancy = {
    role_prefix    = var.tenant_role_prefix
    caller_tenants = { for k, i in azurerm_user_assigned_identity.ingest : i.client_id => k }
  }
  tokens_per_minute   = var.tokens_per_minute_per_tenant
  monthly_token_quota = var.monthly_token_quota_per_tenant

  log_analytics_workspace_id     = module.observability.workspace_id
  app_insights_id                = module.observability.app_insights_id
  app_insights_connection_string = module.observability.app_insights_connection_string

  depends_on = [module.private_endpoint]
}

# ------------------------------------------------------------------ one front door for every tenant
module "ingress" {
  source                = "../../modules/app-gateway"
  count                 = var.certificate_secret_id == null ? 0 : 1
  name                  = local.n.app_gateway
  waf_policy_name       = local.n.waf_policy
  identity_name         = local.n.identity_agw
  public_ip_name        = local.n.public_ip_agw
  resource_group_name   = azurerm_resource_group.this.name
  location              = var.location
  zones                 = var.zone_redundant ? ["1", "2", "3"] : null
  tags                  = local.tags
  subnet_id             = module.network.agw_subnet_id
  private_ip_address    = cidrhost(cidrsubnet(var.address_space, 2, 2), 10)
  host_name             = var.host_name
  key_vault_id          = module.key_vault.id
  certificate_secret_id = var.certificate_secret_id
  backend_ip            = module.apps.environment_static_ip
  backend_host_header   = module.apps.api_fqdn

  log_analytics_workspace_id = module.observability.workspace_id

  depends_on = [module.private_endpoint]
}
