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
  use_aca    = var.compute_platform == "container_apps"
  use_aks    = var.compute_platform == "aks"

  tags = merge(var.tags, {
    client              = var.client
    isolation_tier      = "1-dedicated" # ADR 0014
    environment         = var.environment
    data_classification = var.data_classification
    cost_center         = var.cost_center
    owner               = var.owner_email
    managed_by          = "terraform"
    stamp               = "ai-advisory-client"
  })

  # privatelink zones per sub-resource. Only created in standalone mode; in landing_zone mode they
  # live in the P&T hub and DNS records are written by policy.
  private_dns_zones = merge(
    {
      vault  = "privatelink.vaultcore.azure.net"
      openai = "privatelink.openai.azure.com"
      blob   = "privatelink.blob.core.windows.net"
      search = "privatelink.search.windows.net"
    },
    local.content_safety ? { cognitiveservices = "privatelink.cognitiveservices.azure.com" } : {}
  )

  use_ai_gateway = var.ai_gateway != null
  content_safety = try(var.ai_gateway.enable_content_safety, false)

  # ---- Client network connectivity (ADR 0013)
  cc                  = var.client_connectivity
  client_routed       = contains(["vpn", "expressroute"], local.cc.type) # through P&T's shared hub
  client_private_link = local.cc.type == "privatelink"                   # straight to this client's gateway
  landing_zone        = var.connectivity_mode == "landing_zone"

  # One list drives three controls in the spoke (the hub firewall rule is the fourth, in P&T's hub):
  # the App Gateway NSG, the WAF allow-list and the return routes. A client routed through the hub is
  # admitted from its own ranges only, never from the VirtualNetwork tag (which would also match every
  # other client's network that the shared gateway has learned).
  ingress_sources = (
    local.client_routed ? local.cc.on_prem_prefixes
    : local.client_private_link ? [] # the Private Link subnet is added by the network module
    : try(var.ingress.allowed_source_prefixes, ["VirtualNetwork"])
  )
  waf_allowed_cidrs = (
    local.client_routed && length(try(var.ingress.allowed_client_cidrs, [])) == 0
    ? local.cc.on_prem_prefixes
    : try(var.ingress.allowed_client_cidrs, [])
  )
  ingress_ip = var.ingress == null ? null : cidrhost(cidrsubnet(var.address_space, 2, 2), 10)
}

# Rules that span several inputs. Checked at plan time so a bad client config fails in the PR.
module "client_network_overlap" {
  source = "../../modules/cidr-overlap"
  prefixes = {
    "spoke ${var.address_space}" = [var.address_space]
    "client network"             = local.client_routed ? local.cc.on_prem_prefixes : []
  }
}

resource "terraform_data" "client_connectivity_contract" {
  # Stored in state: what was agreed with P&T for this client's network path.
  input = local.client_routed ? {
    type             = local.cc.type
    on_prem_prefixes = local.cc.on_prem_prefixes
  } : { type = local.cc.type, on_prem_prefixes = [] }

  lifecycle {
    precondition {
      condition     = !local.client_routed || local.landing_zone
      error_message = "vpn and expressroute go through P&T's hub, so they need connectivity_mode = landing_zone. For a standalone demo use privatelink."
    }
    precondition {
      condition     = local.cc.type == "none" || var.ingress != null
      error_message = "client_connectivity needs ingress: the client's network connects to this client's App Gateway."
    }
    precondition {
      condition     = local.cc.type == "none" || try(var.ingress.frontend_mode, "private") == "private"
      error_message = "A private path from the client's network goes with a private frontend (ingress.frontend_mode = private)."
    }
    precondition {
      condition     = length(module.client_network_overlap.overlaps) == 0
      error_message = "Client network overlaps this spoke: ${join("; ", module.client_network_overlap.overlaps)}. Use vpn.nat to translate it, or privatelink."
    }
  }
}

# Warning only: a routed client can't reach the spoke until gateway transit is on (onboarding step 3).
check "gateway_transit_for_routed_clients" {
  assert {
    condition     = !(local.client_routed && local.landing_zone) || try(var.hub.gateway_transit, false)
    error_message = "client_connectivity is ${local.cc.type} but hub.gateway_transit is false: hand output.hub_connectivity_request to P&T, then set gateway_transit = true once their side is applied."
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
  compute_platform    = var.compute_platform
  enable_apim_subnet  = local.use_ai_gateway
  nsg_apim_name       = local.n.nsg_apim

  enable_ingress_subnet           = var.ingress != null
  nsg_agw_name                    = local.n.nsg_agw
  ingress_allowed_source_prefixes = local.ingress_sources

  # Client network connectivity (ADR 0013)
  use_remote_gateways        = local.client_routed && try(var.hub.gateway_transit, false)
  client_network_prefixes    = local.client_routed ? local.cc.on_prem_prefixes : []
  enable_private_link_subnet = local.client_private_link

  tags = local.tags
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
    # With the AI gateway on, the app has NO direct model access: only the gateway does, so its
    # token limits, safety checks and logs can't be bypassed (ADR 0012).
    local.use_ai_gateway ? {} : {
      openai = { scope = module.ai.openai_id, role = "Cognitive Services OpenAI User" }
    },
    {
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
# Same app settings whichever platform runs the app. On AKS they're published as a ConfigMap
# (see kubernetes/), on Container Apps they're environment variables.
locals {
  app_settings = merge(
    {
      CLIENT_CODE            = var.client
      AZURE_OPENAI_ENDPOINT  = local.use_ai_gateway ? module.ai_gateway[0].gateway_url : module.ai.openai_endpoint
      AI_GATEWAY_ENABLED     = tostring(local.use_ai_gateway)
      AZURE_KEY_VAULT_URI    = module.key_vault.uri
      AZURE_STORAGE_BLOB_URL = module.storage.blob_endpoint
    },
    var.enable_search ? { AZURE_SEARCH_ENDPOINT = module.ai.search_endpoint } : {}
  )

  # Static IP for the AKS internal NGINX load balancer (app routing add-on), set in
  # kubernetes/ingress-controller.yaml. App Gateway targets it.
  aks_ingress_ip = cidrhost(module.network.workload_subnet_prefix, 250)
}

module "apps" {
  source                             = "../../modules/container-apps"
  count                              = local.use_aca ? 1 : 0
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
  env                                = local.app_settings
  tags                               = local.tags

  depends_on = [module.app_identity, module.private_endpoint]
}

module "aks" {
  source                      = "../../modules/aks"
  count                       = local.use_aks ? 1 : 0
  name                        = local.n.aks
  control_plane_identity_name = local.n.identity_aks_cp
  resource_group_name         = azurerm_resource_group.this.name
  node_resource_group_name    = local.n.aks_node_rg
  location                    = var.location
  tenant_id                   = data.azurerm_client_config.current.tenant_id
  kubernetes_version          = var.aks.kubernetes_version
  subnet_id                   = module.network.workload_subnet_id
  route_table_id              = module.network.route_table_id
  egress_via_hub_firewall     = var.connectivity_mode == "landing_zone"
  private_dns_zone_id         = var.aks.private_dns_zone_id
  zones                       = var.zone_redundant ? ["1", "2", "3"] : null
  system_pool                 = var.aks.system_pool
  user_pool                   = var.aks.user_pool
  gpu_pool                    = var.aks.gpu_pool
  admin_group_object_ids      = var.aks.admin_group_object_ids
  reader_group_object_id      = var.reader_group_object_id
  log_analytics_workspace_id  = module.observability.workspace_id
  acr_id                      = var.acr == null ? null : var.acr.id
  key_vault_id                = module.key_vault.id
  tags                        = local.tags

  # The same managed identity the app would use on Container Apps, now trusted for one
  # Kubernetes service account in this client's cluster only.
  workload_identities = {
    api = {
      identity_id     = module.app_identity.id
      namespace       = var.aks.app_namespace
      service_account = var.aks.app_service_account
    }
  }

  depends_on = [module.private_endpoint]
}

# ------------------------------------------------------------------ AI gateway (ADR 0012)
module "ai_gateway" {
  source              = "../../modules/ai-gateway"
  count               = local.use_ai_gateway ? 1 : 0
  name                = local.n.ai_gateway
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  client              = var.client
  sku_name            = var.ai_gateway.sku_name
  zones               = var.zone_redundant ? ["1", "2", "3"] : null
  publisher_email     = var.owner_email
  subnet_id           = module.network.apim_subnet_id
  vnet_id             = module.network.vnet_id
  tags                = local.tags

  # Primary = this client's own AOAI account; extra backends (e.g. a second region in the same
  # data zone, or a PTU account) come from client config. All in this client's subscription.
  backends = concat(
    [{ name = "aoai-primary", url = module.ai.openai_endpoint, resource_id = module.ai.openai_id }],
    var.ai_gateway.additional_backends,
  )
  allowed_caller_client_ids = [module.app_identity.client_id]
  tokens_per_minute         = var.ai_gateway.tokens_per_minute
  monthly_token_quota       = var.ai_gateway.monthly_token_quota
  log_request_bodies_bytes  = var.ai_gateway.log_request_bodies_bytes

  enable_content_safety                  = local.content_safety
  content_safety_name                    = local.n.content_safety
  pe_subnet_id                           = module.network.pe_subnet_id
  cognitiveservices_private_dns_zone_ids = local.standalone && local.content_safety ? [azurerm_private_dns_zone.this["cognitiveservices"].id] : []

  log_analytics_workspace_id     = module.observability.workspace_id
  app_insights_id                = module.observability.app_insights_id
  app_insights_connection_string = module.observability.app_insights_connection_string

  depends_on = [module.private_endpoint]
}

# ------------------------------------------------------------------ ingress (ADR 0010)
module "ingress" {
  source              = "../../modules/app-gateway"
  count               = var.ingress == null ? 0 : 1
  name                = local.n.app_gateway
  waf_policy_name     = local.n.waf_policy
  identity_name       = local.n.identity_agw
  public_ip_name      = local.n.public_ip_agw
  resource_group_name = azurerm_resource_group.this.name
  location            = var.location
  zones               = var.zone_redundant ? ["1", "2", "3"] : null
  tags                = local.tags

  subnet_id              = module.network.agw_subnet_id
  private_ip_address     = local.ingress_ip
  frontend_mode          = var.ingress.frontend_mode
  host_name              = var.ingress.host_name
  enable_private_link    = local.client_private_link
  private_link_subnet_id = local.client_private_link ? module.network.agw_private_link_subnet_id : null

  key_vault_id          = module.key_vault.id
  certificate_secret_id = var.ingress.certificate_secret_id

  # Target the backend by IP and send the right host header, so App Gateway never depends on
  # resolving the Container Apps environment's private DNS zone through the hub resolver.
  backend_ip          = local.use_aca ? module.apps[0].environment_static_ip : local.aks_ingress_ip
  backend_host_header = local.use_aca ? module.apps[0].api_fqdn : var.ingress.host_name
  health_probe_path   = var.ingress.health_probe_path

  waf_mode                    = var.ingress.waf_mode
  waf_prompt_field_exclusions = var.ingress.waf_prompt_field_exclusions
  rate_limit_per_minute       = var.ingress.rate_limit_per_minute
  allowed_client_cidrs        = local.waf_allowed_cidrs
  autoscale = {
    min_capacity = var.ingress.min_capacity
    max_capacity = var.ingress.max_capacity
  }

  log_analytics_workspace_id = module.observability.workspace_id

  depends_on = [module.private_endpoint] # needs the Key Vault private endpoint to fetch its certificate
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
