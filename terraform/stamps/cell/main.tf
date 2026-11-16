# Tier 2: shared cell (ADR 0014). Read variables.tf first.
#
# Shared here (processes client traffic, stores no client data):
#   VNet, App Gateway WAF_v2 (a listener + WAF policy per client), Container Apps environment (an app per
#   client), API Management AI gateway (an API per client), AI Search (an index per client), a vault for TLS
#   certificates, and a workspace for shared-infrastructure logs.
# Not here: anything that stores client data. That is in each client's own resource group (cell-client).

data "azurerm_client_config" "current" {}

module "naming" {
  source      = "../../modules/naming"
  client      = var.cell
  environment = var.environment
  location    = var.location
  unique_seed = var.subscription_id
}

locals {
  n          = module.naming.names
  standalone = var.connectivity_mode == "standalone"

  tags = merge(var.tags, {
    client              = "shared" # required RG tag (policy); per-client resources here carry their own client tag
    cell                = var.cell
    isolation_tier      = "2-shared-cell"
    environment         = var.environment
    data_classification = "none-at-rest" # shared infra: client data passes through, never stored here
    cost_center         = var.cost_center
    owner               = var.owner_email
    managed_by          = "terraform"
    stamp               = "ai-advisory-cell"
  })

  routed          = { for k, c in var.clients : k => c if length(c.on_prem_prefixes) > 0 }
  routed_prefixes = distinct(flatten([for c in values(local.routed) : c.on_prem_prefixes]))
  public_cidrs    = distinct(flatten([for c in values(var.clients) : c.allowed_client_cidrs if c.frontend == "public"]))
  agw_sources     = distinct(concat(local.routed_prefixes, local.public_cidrs))
  agw_private_ip  = cidrhost(cidrsubnet(var.address_space, 2, 2), 10)
  agw_subnet_cidr = cidrsubnet(var.address_space, 2, 2)
  gateway_ids     = [for c in values(var.clients) : c.gateway_identity_id]

  # Roles stamps/cell-client assigns inside the client's resource group (AcrPull is granted on the platform
  # registry by the platform pipeline, as for Tier 1).
  client_assignable_roles = [
    "Key Vault Secrets User",
    "Storage Blob Data Contributor",
    "Monitoring Metrics Publisher",
    "Cognitive Services OpenAI User",
    "Managed Identity Operator",
    "Reader",
  ]
  client_role_guids     = join(", ", sort([for r in data.azurerm_role_definition.client_assignable : basename(r.id)]))
  client_rbac_condition = <<-EOT
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/write'})
     )
     OR
     (
      @Request[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.client_role_guids}}
     )
    )
    AND
    (
     (
      !(ActionMatches{'Microsoft.Authorization/roleAssignments/delete'})
     )
     OR
     (
      @Resource[Microsoft.Authorization/roleAssignments:RoleDefinitionId] ForAnyOfAnyValues:GuidEquals {${local.client_role_guids}}
     )
    )
  EOT
  apim_has_clients      = length(var.clients) > 0

  private_dns_zones = {
    vault  = "privatelink.vaultcore.azure.net"
    openai = "privatelink.openai.azure.com"
    blob   = "privatelink.blob.core.windows.net"
    search = "privatelink.search.windows.net"
  }
}

# Routed clients share one hub and one frontend IP, so their ranges must not clash with each other or the cell.
module "overlap" {
  source = "../../modules/cidr-overlap"
  prefixes = merge(
    { "cell ${var.address_space}" = [var.address_space] },
    { for k, c in local.routed : "${k} network" => c.on_prem_prefixes },
  )
}

resource "terraform_data" "cell_contract" {
  input = { clients = sort(keys(var.clients)), slots = sort(keys(var.client_slots)), max_clients = var.max_clients }

  lifecycle {
    precondition {
      condition     = length(module.overlap.overlaps) == 0
      error_message = "Client networks overlap: ${join("; ", module.overlap.overlaps)}."
    }
    precondition {
      condition     = length(setsubtract(keys(var.clients), keys(var.client_slots))) == 0
      error_message = "Clients without a slot: ${join(", ", setsubtract(keys(var.clients), keys(var.client_slots)))}. Add them to client_slots first (onboarding step 1)."
    }
    precondition {
      condition     = length(local.routed) == 0 || var.connectivity_mode == "landing_zone"
      error_message = "Clients with on_prem_prefixes come through P&T's hub, so the cell needs connectivity_mode = landing_zone."
    }
  }
}

resource "azurerm_resource_group" "shared" {
  name     = local.n.resource_group
  location = var.location
  tags     = local.tags
}

# ------------------------------------------------------------------ network (same module and layout as a Tier 1 spoke)
module "network" {
  source              = "../../modules/spoke-network"
  name                = local.n.vnet
  resource_group_name = azurerm_resource_group.shared.name
  location            = var.location
  address_space       = var.address_space
  nsg_apps_name       = local.n.nsg_apps
  nsg_pe_name         = local.n.nsg_pe
  route_table_name    = local.n.route_table
  hub                 = var.connectivity_mode == "landing_zone" ? var.hub : null
  compute_platform    = "container_apps"
  enable_apim_subnet  = true
  nsg_apim_name       = local.n.nsg_apim

  enable_ingress_subnet           = true
  nsg_agw_name                    = local.n.nsg_agw
  ingress_allowed_source_prefixes = length(local.agw_sources) > 0 ? local.agw_sources : ["VirtualNetwork"]
  use_remote_gateways             = length(local.routed) > 0 && try(var.hub.gateway_transit, false)
  client_network_prefixes         = local.routed_prefixes
  enable_private_link_subnet      = var.enable_private_link

  tags = local.tags
}

resource "azurerm_private_dns_zone" "this" {
  for_each            = local.standalone ? local.private_dns_zones : {}
  name                = each.value
  resource_group_name = azurerm_resource_group.shared.name
  tags                = local.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each              = azurerm_private_dns_zone.this
  name                  = "link-${module.network.vnet_name}"
  resource_group_name   = azurerm_resource_group.shared.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = module.network.vnet_id
  registration_enabled  = false
  tags                  = local.tags
}

# ------------------------------------------------------------------ onboarding step 1: a resource group per client
# The cell's own deployment identity creates the client's resource group and hands it to the client's
# deployment identity. That identity can then build the client's data stores (stamps/cell-client) but has no
# rights on the cell's shared resources or on any other client's resource group.
module "client_naming" {
  for_each    = var.client_slots
  source      = "../../modules/naming"
  client      = each.key
  environment = var.environment
  location    = var.location
  unique_seed = "${var.subscription_id}/${each.key}" # same seed as stamps/cell-client, so the names match
}

resource "azurerm_resource_group" "client" {
  for_each = var.client_slots
  name     = module.client_naming[each.key].names.resource_group
  location = var.location
  tags = merge(var.tags, {
    client              = each.key
    cell                = var.cell
    isolation_tier      = "2-shared-cell"
    environment         = var.environment
    data_classification = each.value.data_classification
    cost_center         = each.value.cost_center
    owner               = each.value.owner_email
    managed_by          = "terraform"
  })
}

resource "azurerm_role_assignment" "client_deployer" {
  for_each             = var.client_slots
  scope                = azurerm_resource_group.client[each.key].id
  role_definition_name = "Contributor"
  principal_id         = each.value.deployer_principal_id
  principal_type       = "ServicePrincipal"
  description          = "Builds ${each.key}'s data stores in its own resource group (stamps/cell-client)."
}

# cell-client grants its identities a few data roles inside its own resource group. Role Based Access Control
# Administrator with a condition: it can create or delete assignments of these roles only, so the client's
# pipeline can't make anyone an Owner, even inside its own resource group.
data "azurerm_role_definition" "client_assignable" {
  for_each = toset(local.client_assignable_roles)
  name     = each.value
}

resource "azurerm_role_assignment" "client_deployer_rbac" {
  for_each             = var.client_slots
  scope                = azurerm_resource_group.client[each.key].id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = each.value.deployer_principal_id
  principal_type       = "ServicePrincipal"
  condition_version    = "2.0"
  condition            = local.client_rbac_condition
  description          = "Can assign only the roles stamps/cell-client uses (ADR 0014)."
}

# Contributor can't create locks, and a private endpoint in the client's resource group has to join the
# cell's snet-pe. Two narrow custom roles instead of Owner or Network Contributor on the shared subnet.
resource "azurerm_role_definition" "client_locks" {
  count       = length(var.client_slots) > 0 ? 1 : 0
  name        = "AI Advisory ${var.cell} client data locks"
  scope       = azurerm_resource_group.shared.id
  description = "Create and remove CanNotDelete locks on a client's data stores (stamps/cell-client)."
  permissions {
    actions = ["Microsoft.Authorization/locks/read", "Microsoft.Authorization/locks/write", "Microsoft.Authorization/locks/delete"]
  }
  assignable_scopes = [for rg in azurerm_resource_group.client : rg.id]
}

resource "azurerm_role_assignment" "client_locks" {
  for_each           = var.client_slots
  scope              = azurerm_resource_group.client[each.key].id
  role_definition_id = azurerm_role_definition.client_locks[0].role_definition_resource_id
  principal_id       = each.value.deployer_principal_id
  principal_type     = "ServicePrincipal"
}

resource "azurerm_role_definition" "pe_join" {
  name        = "AI Advisory ${var.cell} private endpoint join"
  scope       = azurerm_resource_group.shared.id
  description = "Put a private endpoint NIC in the cell's snet-pe and register it in the cell's private DNS zones. Can't change the subnet or the zones."
  permissions {
    actions = [
      "Microsoft.Network/virtualNetworks/subnets/read",
      "Microsoft.Network/virtualNetworks/subnets/join/action",
      "Microsoft.Network/privateDnsZones/read",
      "Microsoft.Network/privateDnsZones/join/action",
    ]
  }
  assignable_scopes = [azurerm_resource_group.shared.id]
}

resource "azurerm_role_assignment" "client_pe_join" {
  for_each = {
    for pair in setproduct(keys(var.client_slots), concat(["subnet"], keys(azurerm_private_dns_zone.this))) :
    "${pair[0]}/${pair[1]}" => { client = pair[0], target = pair[1] }
  }
  scope              = each.value.target == "subnet" ? module.network.pe_subnet_id : azurerm_private_dns_zone.this[each.value.target].id
  role_definition_id = azurerm_role_definition.pe_join.role_definition_resource_id
  principal_id       = var.client_slots[each.value.client].deployer_principal_id
  principal_type     = "ServicePrincipal"
}

# ------------------------------------------------------------------ shared services (no client data at rest)
module "observability" {
  source              = "../../modules/observability"
  law_name            = local.n.log_analytics
  appi_name           = local.n.app_insights
  resource_group_name = azurerm_resource_group.shared.name
  location            = var.location
  retention_in_days   = var.log_retention_days
  tags                = local.tags

  diagnostic_targets = {
    key_vault = module.key_vault.id
    search    = azurerm_search_service.shared.id
  }
}

# Certificates for client host names only. Client secrets live in each client's own vault.
module "key_vault" {
  source              = "../../modules/key-vault"
  name                = local.n.key_vault
  resource_group_name = azurerm_resource_group.shared.name
  location            = var.location
  tenant_id           = data.azurerm_client_config.current.tenant_id
  tags                = local.tags
}

# One search service, one index per client. Index-scoped RBAC (below) keeps each app to its own index.
# Indexers are not used: they run with service-level rights and would bypass index-level RBAC, so
# documents are pushed by each client's app with its own identity.
resource "azurerm_search_service" "shared" {
  #checkov:skip=CKV_AZURE_207:Replica count is a per-cell input (default 2 for the read SLA); 3 for read/write SLA.
  #checkov:skip=CKV_AZURE_208:2 replicas give the query SLA. Index updates are batch, push-only ingestion that retries, so a third unit for the write SLA isn't worth ~USD 245/month per cell.
  name                          = local.n.search
  location                      = var.location
  resource_group_name           = azurerm_resource_group.shared.name
  sku                           = var.search_sku
  replica_count                 = var.search_replica_count
  partition_count               = 1
  public_network_access_enabled = false
  local_authentication_enabled  = false
  tags                          = local.tags

  identity {
    type = "SystemAssigned"
  }
}

module "private_endpoint" {
  source = "../../modules/private-endpoint"
  for_each = {
    kv   = { target = module.key_vault.id, subresource = "vault", zone = "vault" }
    srch = { target = azurerm_search_service.shared.id, subresource = "searchService", zone = "search" }
  }
  name                 = "pe-${module.naming.base}-${each.key}"
  resource_group_name  = azurerm_resource_group.shared.name
  location             = var.location
  subnet_id            = module.network.pe_subnet_id
  target_resource_id   = each.value.target
  subresource_name     = each.value.subresource
  private_dns_zone_ids = local.standalone ? [azurerm_private_dns_zone.this[each.value.zone].id] : []
  tags                 = local.tags
}

resource "azurerm_role_assignment" "index" {
  for_each             = var.clients
  scope                = "${azurerm_search_service.shared.id}/indexes/${each.key}"
  role_definition_name = "Search Index Data Contributor"
  principal_id         = each.value.app_identity_principal_id
  principal_type       = "ServicePrincipal"
}

# ------------------------------------------------------------------ shared Container Apps environment, one app per client
resource "azurerm_container_app_environment" "shared" {
  name                               = local.n.container_app_environment
  location                           = var.location
  resource_group_name                = azurerm_resource_group.shared.name
  log_analytics_workspace_id         = module.observability.workspace_id
  infrastructure_subnet_id           = module.network.workload_subnet_id
  infrastructure_resource_group_name = local.n.container_app_infra_rg
  internal_load_balancer_enabled     = true
  zone_redundancy_enabled            = var.zone_redundant
  tags                               = local.tags

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

resource "azurerm_private_dns_zone" "env" {
  name                = azurerm_container_app_environment.shared.default_domain
  resource_group_name = azurerm_resource_group.shared.name
  tags                = local.tags
}

resource "azurerm_private_dns_a_record" "env_wildcard" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.env.name
  resource_group_name = azurerm_resource_group.shared.name
  ttl                 = 300
  records             = [azurerm_container_app_environment.shared.static_ip_address]
}

resource "azurerm_private_dns_zone_virtual_network_link" "env" {
  name                  = "link-cell"
  resource_group_name   = azurerm_resource_group.shared.name
  private_dns_zone_name = azurerm_private_dns_zone.env.name
  virtual_network_id    = module.network.vnet_id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_container_app" "client" {
  for_each                     = var.clients
  name                         = "ca-${each.key}"
  container_app_environment_id = azurerm_container_app_environment.shared.id
  resource_group_name          = azurerm_resource_group.shared.name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  tags                         = merge(local.tags, { client = each.key })

  # The client's own identity, created in the client's resource group. Its roles reach only that client's data.
  identity {
    type         = "UserAssigned"
    identity_ids = [each.value.app_identity_id]
  }

  dynamic "registry" {
    for_each = var.acr == null ? [] : [1]
    content {
      server   = var.acr.login_server
      identity = each.value.app_identity_id
    }
  }

  secret {
    name  = "appinsights-connection-string"
    value = each.value.app_insights_connection_string # the client's own App Insights
  }

  ingress {
    external_enabled = true # reachable on the VNet; the environment itself is internal
    target_port      = 80
    transport        = "auto"

    # Only the shared App Gateway may call a client's app, so one client's app can't call another's.
    ip_security_restriction {
      name             = "app-gateway-only"
      action           = "Allow"
      ip_address_range = local.agw_subnet_cidr
    }

    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = each.value.min_replicas
    max_replicas = each.value.max_replicas

    container {
      name   = "api"
      image  = each.value.app_image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "AZURE_CLIENT_ID"
        value = each.value.app_identity_client_id
      }
      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "appinsights-connection-string"
      }
      env {
        name  = "CLIENT_CODE"
        value = each.key
      }
      env {
        name  = "TENANCY_MODE"
        value = "single" # same image as Tier 1 and Tier 3; one client per app here
      }
      env {
        name  = "AZURE_OPENAI_ENDPOINT"
        value = "${azurerm_api_management.shared.gateway_url}/${each.key}"
      }
      env {
        name  = "AZURE_KEY_VAULT_URI"
        value = each.value.key_vault_uri
      }
      env {
        name  = "AZURE_STORAGE_BLOB_URL"
        value = each.value.storage_blob_url
      }
      env {
        name  = "AZURE_SEARCH_ENDPOINT"
        value = "https://${azurerm_search_service.shared.name}.search.windows.net"
      }
      env {
        name  = "AZURE_SEARCH_INDEX"
        value = each.key
      }

      liveness_probe {
        transport = "HTTP"
        port      = 80
        path      = "/"
      }
    }
  }
}

# ------------------------------------------------------------------ shared AI gateway, one API per client
resource "azurerm_api_management" "shared" {
  #checkov:skip=CKV_AZURE_174:Internal VNet mode: the gateway has only a private VIP. public_network_access can't be disabled at creation; nothing is exposed publicly.
  name                 = local.n.ai_gateway
  location             = var.location
  resource_group_name  = azurerm_resource_group.shared.name
  publisher_name       = "Chatham AI Advisory"
  publisher_email      = var.owner_email
  sku_name             = var.ai_gateway_sku
  zones                = startswith(var.ai_gateway_sku, "Premium") && var.zone_redundant ? ["1", "2", "3"] : null
  virtual_network_type = "Internal"
  min_api_version      = "2021-08-01"
  tags                 = local.tags

  virtual_network_configuration {
    subnet_id = module.network.apim_subnet_id
  }

  # System identity: telemetry only. One user-assigned identity PER CLIENT, each trusted by that client's
  # Azure OpenAI account alone; a client's API policy names its own identity by client ID.
  identity {
    type         = local.apim_has_clients ? "SystemAssigned, UserAssigned" : "SystemAssigned"
    identity_ids = local.apim_has_clients ? local.gateway_ids : null
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
    enabled = false
    terms_of_service {
      consent_required = false
      enabled          = false
    }
  }
}

resource "azurerm_private_dns_zone" "gateway" {
  name                = "${local.n.ai_gateway}.azure-api.net"
  resource_group_name = azurerm_resource_group.shared.name
  tags                = local.tags
}

resource "azurerm_private_dns_a_record" "gateway" {
  name                = "@"
  zone_name           = azurerm_private_dns_zone.gateway.name
  resource_group_name = azurerm_resource_group.shared.name
  ttl                 = 300
  records             = azurerm_api_management.shared.private_ip_addresses
}

resource "azurerm_private_dns_zone_virtual_network_link" "gateway" {
  name                  = "link-cell"
  resource_group_name   = azurerm_resource_group.shared.name
  private_dns_zone_name = azurerm_private_dns_zone.gateway.name
  virtual_network_id    = module.network.vnet_id
  registration_enabled  = false
  tags                  = local.tags
}

resource "azurerm_api_management_backend" "client" {
  #checkov:skip=CKV_AZURE_215:URL is always https (the client's Azure OpenAI endpoint, interpolated so Checkov cannot read it); protocol "http" means HTTP-based rather than SOAP.
  for_each            = var.clients
  name                = "aoai-${each.key}"
  resource_group_name = azurerm_resource_group.shared.name
  api_management_name = azurerm_api_management.shared.name
  protocol            = "http"
  url                 = "${trimsuffix(each.value.openai_endpoint, "/")}/openai"
  description         = "Azure OpenAI account of client ${each.key} (in that client's resource group)"

  tls {
    validate_certificate_chain = true
    validate_certificate_name  = true
  }

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

resource "azurerm_api_management_api" "client" {
  for_each              = var.clients
  name                  = "openai-${each.key}"
  resource_group_name   = azurerm_resource_group.shared.name
  api_management_name   = azurerm_api_management.shared.name
  revision              = "1"
  display_name          = "Azure OpenAI (${each.key})"
  path                  = "${each.key}/openai"
  protocols             = ["https"]
  subscription_required = false

  import {
    content_format = "openapi+json-link"
    content_value  = "https://raw.githubusercontent.com/Azure/azure-rest-api-specs/main/specification/cognitiveservices/data-plane/AzureOpenAI/inference/stable/2024-10-21/inference.json"
  }
}

locals {
  gateway_policies = {
    for k, c in var.clients : k => templatefile("${path.module}/gateway-policy.xml.tftpl", {
      client            = k
      tenant_id         = data.azurerm_client_config.current.tenant_id
      app_client_id     = c.app_identity_client_id
      gateway_client_id = c.gateway_identity_client_id
      tpm               = c.tokens_per_minute
      quota             = c.monthly_token_quota
    })
  }
}

resource "azurerm_api_management_api_policy" "client" {
  for_each            = var.clients
  api_name            = azurerm_api_management_api.client[each.key].name
  api_management_name = azurerm_api_management.shared.name
  resource_group_name = azurerm_resource_group.shared.name
  xml_content         = local.gateway_policies[each.key]

  depends_on = [azurerm_api_management_backend.client]
}

resource "azurerm_role_assignment" "gateway_to_appinsights" {
  scope                = module.observability.app_insights_id
  role_definition_name = "Monitoring Metrics Publisher"
  principal_id         = azurerm_api_management.shared.identity[0].principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_api_management_logger" "appinsights" {
  name                = "cell-appinsights"
  resource_group_name = azurerm_resource_group.shared.name
  api_management_name = azurerm_api_management.shared.name
  resource_id         = module.observability.app_insights_id

  application_insights {
    connection_string = module.observability.app_insights_connection_string
  }

  depends_on = [azurerm_role_assignment.gateway_to_appinsights]
}

resource "azurerm_api_management_api_diagnostic" "client" {
  for_each                 = var.clients
  identifier               = "applicationinsights"
  resource_group_name      = azurerm_resource_group.shared.name
  api_management_name      = azurerm_api_management.shared.name
  api_name                 = azurerm_api_management_api.client[each.key].name
  api_management_logger_id = azurerm_api_management_logger.appinsights.id
  sampling_percentage      = 100
  always_log_errors        = true
  log_client_ip            = true
  verbosity                = "information"

  # Shared workspace: prompt and response bodies are never logged here.
  frontend_request {
    body_bytes     = 0
    headers_to_log = ["x-ms-client-request-id"]
  }

  frontend_response {
    body_bytes     = 0
    headers_to_log = ["x-ratelimit-remaining-tokens", "x-tokens-consumed"]
  }
}

resource "azurerm_monitor_diagnostic_setting" "gateway" {
  name                           = "diag-to-cell-law"
  target_resource_id             = azurerm_api_management.shared.id
  log_analytics_workspace_id     = module.observability.workspace_id
  log_analytics_destination_type = "Dedicated"

  enabled_log {
    category_group = "allLogs"
  }
}

# ------------------------------------------------------------------ shared App Gateway, one site per client
module "ingress" {
  count               = length(var.clients) > 0 ? 1 : 0 # a new cell has no sites until its first client registers (step 3)
  source              = "../../modules/shared-app-gateway"
  name                = local.n.app_gateway
  identity_name       = local.n.identity_agw
  public_ip_name      = local.n.public_ip_agw
  resource_group_name = azurerm_resource_group.shared.name
  location            = var.location
  zones               = var.zone_redundant ? ["1", "2", "3"] : null
  tags                = local.tags

  subnet_id              = module.network.agw_subnet_id
  private_ip_address     = local.agw_private_ip
  enable_private_link    = var.enable_private_link
  private_link_subnet_id = var.enable_private_link ? module.network.agw_private_link_subnet_id : null
  key_vault_id           = module.key_vault.id
  backend_ip             = azurerm_container_app_environment.shared.static_ip_address

  sites = {
    for k, c in var.clients : k => {
      host_name             = c.host_name
      certificate_secret_id = c.certificate_secret_id
      backend_host_header   = azurerm_container_app.client[k].ingress[0].fqdn
      frontend              = c.frontend
      waf_mode              = c.waf_mode
      allowed_client_cidrs  = c.frontend == "public" ? c.allowed_client_cidrs : c.on_prem_prefixes
      rate_limit_per_minute = c.rate_limit_per_minute
    }
  }

  log_analytics_workspace_id = module.observability.workspace_id

  depends_on = [module.private_endpoint]
}
