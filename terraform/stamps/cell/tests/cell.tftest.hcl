# Offline tests for a Tier 2 shared cell (mocked provider, no Azure access). They assert the controls that
# keep clients apart when the gateway, compute and edge are shared (ADR 0014).

mock_provider "azurerm" {
  mock_data "azurerm_client_config" {
    defaults = {
      tenant_id = "00000000-0000-0000-0000-000000000000"
    }
  }
  mock_resource "azurerm_container_app_environment" {
    defaults = {
      default_domain    = "calm-river-123.eastus2.azurecontainerapps.io"
      static_ip_address = "10.110.0.10"
    }
  }
  mock_resource "azurerm_api_management" {
    defaults = {
      gateway_url          = "https://apim-cell01-prd-eus2-ab12.azure-api.net"
      private_ip_addresses = ["10.110.1.68"]
    }
  }
}

variables {
  cell            = "cell01"
  subscription_id = "11111111-1111-1111-1111-111111111111"
  address_space   = "10.110.0.0/22"
  cost_center     = "AI-ADVISORY-CELL01"
  owner_email     = "platform@example.com"

  client_slots = {
    northwind = {
      deployer_principal_id = "d1000000-0000-0000-0000-00000000000d"
      cost_center           = "AI-ADVISORY-NORTHWIND"
      owner_email           = "northwind-engagement@example.com"
      data_classification   = "confidential"
    }
    tailspin = {
      deployer_principal_id = "d2000000-0000-0000-0000-00000000000d"
      cost_center           = "AI-ADVISORY-TAILSPIN"
      owner_email           = "tailspin-engagement@example.com"
      data_classification   = "confidential"
    }
    litware = {
      deployer_principal_id = "d3000000-0000-0000-0000-00000000000d"
      cost_center           = "AI-ADVISORY-LITWARE"
      owner_email           = "litware-engagement@example.com"
      data_classification   = "internal"
    }
  }

  clients = {
    northwind = {
      host_name                      = "northwind.ai.chatham.example.com"
      certificate_secret_id          = "https://kv-cell01.vault.azure.net/secrets/northwind-ai-tls"
      app_image                      = "craiadv.azurecr.io/advisor-api@sha256:1111111111111111111111111111111111111111111111111111111111111111"
      app_identity_id                = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-northwind-prd-eus2/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-northwind-prd-eus2-app"
      app_identity_client_id         = "a0000000-0000-0000-0000-00000000000a"
      app_identity_principal_id      = "a0000000-0000-0000-0000-0000000000aa"
      gateway_identity_id            = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-northwind-prd-eus2/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-northwind-prd-eus2-gw"
      gateway_identity_client_id     = "a0000000-0000-0000-0000-00000000000b"
      openai_endpoint                = "https://oai-northwind-prd-eus2-1a2b.openai.azure.com/"
      key_vault_uri                  = "https://kv-northwind-prd-eus2-1a2b.vault.azure.net/"
      storage_blob_url               = "https://stnorthwindprdeus21a2b.blob.core.windows.net/"
      app_insights_connection_string = "InstrumentationKey=a0000000-0000-0000-0000-000000000000"
      ingest_identity_id             = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-northwind-prd-eus2/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-northwind-prd-eus2-ingest"
      ingest_identity_client_id      = "a0000000-0000-0000-0000-00000000000c"
      ingest_identity_principal_id   = "a0000000-0000-0000-0000-0000000000cc"
    }
    tailspin = {
      host_name                      = "tailspin.ai.chatham.example.com"
      certificate_secret_id          = "https://kv-cell01.vault.azure.net/secrets/tailspin-ai-tls"
      app_image                      = "craiadv.azurecr.io/advisor-api@sha256:1111111111111111111111111111111111111111111111111111111111111111"
      min_replicas                   = 0
      tokens_per_minute              = 20000
      app_identity_id                = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-tailspin-prd-eus2/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-tailspin-prd-eus2-app"
      app_identity_client_id         = "b0000000-0000-0000-0000-00000000000a"
      app_identity_principal_id      = "b0000000-0000-0000-0000-0000000000aa"
      gateway_identity_id            = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-tailspin-prd-eus2/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-tailspin-prd-eus2-gw"
      gateway_identity_client_id     = "b0000000-0000-0000-0000-00000000000b"
      openai_endpoint                = "https://oai-tailspin-prd-eus2-3c4d.openai.azure.com/"
      key_vault_uri                  = "https://kv-tailspin-prd-eus2-3c4d.vault.azure.net/"
      storage_blob_url               = "https://sttailspinprdeus23c4d.blob.core.windows.net/"
      app_insights_connection_string = "InstrumentationKey=b0000000-0000-0000-0000-000000000000"
      ingest_identity_id             = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-tailspin-prd-eus2/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-tailspin-prd-eus2-ingest"
      ingest_identity_client_id      = "b0000000-0000-0000-0000-00000000000c"
      ingest_identity_principal_id   = "b0000000-0000-0000-0000-0000000000cc"
    }
    litware = {
      host_name                      = "litware.ai.chatham.example.com"
      certificate_secret_id          = "https://kv-cell01.vault.azure.net/secrets/litware-ai-tls"
      frontend                       = "public"
      allowed_client_cidrs           = ["203.0.113.0/24"]
      app_image                      = "craiadv.azurecr.io/advisor-api@sha256:1111111111111111111111111111111111111111111111111111111111111111"
      app_identity_id                = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-litware-prd-eus2/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-litware-prd-eus2-app"
      app_identity_client_id         = "c0000000-0000-0000-0000-00000000000a"
      app_identity_principal_id      = "c0000000-0000-0000-0000-0000000000aa"
      gateway_identity_id            = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-litware-prd-eus2/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-litware-prd-eus2-gw"
      gateway_identity_client_id     = "c0000000-0000-0000-0000-00000000000b"
      openai_endpoint                = "https://oai-litware-prd-eus2-5e6f.openai.azure.com/"
      key_vault_uri                  = "https://kv-litware-prd-eus2-5e6f.vault.azure.net/"
      storage_blob_url               = "https://stlitwareprdeus25e6f.blob.core.windows.net/"
      app_insights_connection_string = "InstrumentationKey=c0000000-0000-0000-0000-000000000000"
    }
  }
}

run "every_client_gets_its_own_app_api_backend_and_waf_policy" {
  command = plan

  assert {
    condition     = length(azurerm_container_app.client) == 3 && length(azurerm_api_management_api.client) == 3 && length(azurerm_api_management_backend.client) == 3
    error_message = "One container app, one gateway API and one model backend per client."
  }
  assert {
    condition     = length(output.site_waf_policy_ids) == 3
    error_message = "One WAF policy per client, so tuning one never changes another."
  }
  assert {
    condition     = azurerm_api_management_api.client["northwind"].path == "northwind/openai"
    error_message = "Each client has its own API path on the shared gateway."
  }
  assert {
    condition     = azurerm_api_management_backend.client["tailspin"].url == "https://oai-tailspin-prd-eus2-3c4d.openai.azure.com/openai"
    error_message = "A client's backend is that client's own Azure OpenAI account."
  }
}

run "gateway_api_admits_and_acts_as_its_own_client_only" {
  command = plan

  assert {
    condition = alltrue([for k, c in var.clients :
      strcontains(output.gateway_policies[k], "<application-id>${c.app_identity_client_id}</application-id>") &&
      strcontains(output.gateway_policies[k], "client-id=\"${c.gateway_identity_client_id}\"") &&
      strcontains(output.gateway_policies[k], "backend-id=\"aoai-${k}\"")
    ])
    error_message = "Each API must accept only its client's app identity and call only its client's model as its client's gateway identity."
  }
  assert {
    condition = alltrue(flatten([for k, c in var.clients : [for o, oc in var.clients :
      !strcontains(output.gateway_policies[k], oc.app_identity_client_id) && !strcontains(output.gateway_policies[k], oc.gateway_identity_client_id)
    if o != k]]))
    error_message = "No client's policy may mention another client's identities."
  }
  assert {
    condition     = toset(azurerm_api_management.shared.identity[0].identity_ids) == toset([for c in values(var.clients) : c.gateway_identity_id])
    error_message = "The shared gateway holds exactly the clients' gateway identities."
  }
  assert {
    condition     = alltrue([for d in azurerm_api_management_api_diagnostic.client : d.frontend_request[0].body_bytes == 0 && d.frontend_response[0].body_bytes == 0])
    error_message = "A shared gateway never logs prompt or response bodies."
  }
}

run "apps_only_accept_the_app_gateway_and_run_as_their_client" {
  command = plan

  assert {
    condition = alltrue([for k, a in azurerm_container_app.client :
      length(a.ingress[0].ip_security_restriction) == 1 &&
      a.ingress[0].ip_security_restriction[0].action == "Allow" &&
      a.ingress[0].ip_security_restriction[0].ip_address_range == "10.110.2.0/24"
    ])
    error_message = "Client apps must accept traffic from the App Gateway subnet only, so apps can't call each other."
  }
  assert {
    condition     = alltrue([for k, a in azurerm_container_app.client : toset(a.identity[0].identity_ids) == toset([var.clients[k].app_identity_id])])
    error_message = "Each app runs as its own client's identity and no other."
  }
}

run "cell_holds_no_model_or_data_roles" {
  command = plan

  assert {
    condition     = alltrue([for r in azurerm_role_assignment.index : r.role_definition_name == "Search Index Data Contributor"])
    error_message = "The only data role the cell grants is a client's app on its own search index."
  }
  assert {
    condition     = alltrue([for k, r in azurerm_role_assignment.index : r.principal_id == var.clients[k].app_identity_principal_id])
    error_message = "Each client's index role goes to that client's own app identity (scope: <search>/indexes/<client>, see main.tf)."
  }
}

run "full_cell_is_refused" {
  command = plan

  variables {
    max_clients = 2
  }

  expect_failures = [var.clients, var.client_slots]
}

run "shared_host_name_is_refused" {
  command = plan

  variables {
    clients = {
      northwind = merge(var.clients["northwind"], {})
      tailspin  = merge(var.clients["tailspin"], { host_name = "northwind.ai.chatham.example.com" })
    }
  }

  expect_failures = [var.clients]
}

run "routed_clients_need_the_hub" {
  command = plan

  variables {
    clients = {
      northwind = merge(var.clients["northwind"], { on_prem_prefixes = ["172.16.0.0/16"] })
    }
  }

  expect_failures = [terraform_data.cell_contract]
}

run "each_client_pipeline_gets_its_own_resource_group_and_nothing_else" {
  command = plan

  assert {
    condition     = azurerm_resource_group.client["northwind"].name == "rg-northwind-prd-eus2"
    error_message = "The cell must create the same resource group name stamps/cell-client deploys into."
  }
  assert {
    condition = alltrue([
      for rg in concat(values(azurerm_resource_group.client), [azurerm_resource_group.shared]) :
      length(setsubtract(["client", "cost_center", "data_classification", "owner"], keys(rg.tags))) == 0
    ])
    error_message = "Every resource group needs the tags P&T's policy requires (policy/require-resource-group-tags.json)."
  }
  assert {
    condition     = alltrue([for k, r in azurerm_role_assignment.client_deployer : r.principal_id == var.client_slots[k].deployer_principal_id && r.role_definition_name == "Contributor"])
    error_message = "Each client's deployment identity gets Contributor, on its own resource group only."
  }
  assert {
    condition     = length(setintersection(keys(data.azurerm_role_definition.client_assignable), ["Owner", "User Access Administrator", "Role Based Access Control Administrator", "Contributor"])) == 0
    error_message = "A client's pipeline must not be able to hand out privileged roles."
  }
  assert {
    condition     = alltrue([for r in azurerm_role_assignment.client_deployer_rbac : r.condition_version == "2.0" && strcontains(r.condition, "ForAnyOfAnyValues:GuidEquals")])
    error_message = "RBAC Administrator for a client's pipeline must be constrained to the listed roles."
  }
  assert {
    condition     = length(azurerm_role_assignment.client_pe_join) == 3 * (1 + length(azurerm_private_dns_zone.this))
    error_message = "Standalone cell: each client's pipeline may join snet-pe and register in the cell's DNS zones, nothing more."
  }
}

run "new_cell_with_slots_but_no_clients_yet" {
  command = plan

  variables {
    connectivity_mode = "landing_zone"
    hub = {
      vnet_id             = "/subscriptions/33333333-3333-3333-3333-333333333333/resourceGroups/rg-hub/providers/Microsoft.Network/virtualNetworks/vnet-hub"
      firewall_private_ip = "10.0.0.4"
      dns_servers         = ["10.0.1.4"]
    }
    clients = {}
  }

  assert {
    condition     = length(module.ingress) == 0 && length(azurerm_resource_group.client) == 3
    error_message = "Step 1 must work on an empty cell: resource groups first, gateway sites when clients register."
  }
  assert {
    condition     = length(azurerm_role_assignment.client_pe_join) == 3
    error_message = "Landing zone: P&T's policy registers DNS, so client pipelines only join snet-pe."
  }
}

run "client_without_a_slot_is_refused" {
  command = plan

  variables {
    client_slots = {
      northwind = {
        deployer_principal_id = "d1000000-0000-0000-0000-00000000000d"
        cost_center           = "AI-ADVISORY-NORTHWIND"
        owner_email           = "northwind-engagement@example.com"
        data_classification   = "confidential"
      }
    }
  }

  expect_failures = [terraform_data.cell_contract]
}

# ---------------------------------------------------------------- document ingestion (ADR 0015)

run "ingestion_jobs_run_as_each_clients_own_identity" {
  command = plan

  variables {
    ingest_image = "craiadv.azurecr.io/advisor-ingest@sha256:2222222222222222222222222222222222222222222222222222222222222222"
  }

  assert {
    condition     = toset(keys(module.ingestion[0].job_names)) == toset(["northwind", "tailspin"])
    error_message = "Clients that registered an ingestion identity get a job; litware (none) keeps loading its index from its app."
  }
  assert {
    condition = alltrue([for k, s in module.ingestion[0].settings :
      s["AZURE_CLIENT_ID"] == var.clients[k].ingest_identity_client_id && s["AZURE_SEARCH_INDEX"] == k &&
      s["AZURE_STORAGE_BLOB_URL"] == var.clients[k].storage_blob_url && s["MANAGE_INDEX"] == "false"
    ])
    error_message = "Each job runs as its own client's ingestion identity, on that client's storage and index, and can't change index definitions."
  }
  assert {
    condition     = alltrue([for k, r in azurerm_role_assignment.ingest_index : r.principal_id == var.clients[k].ingest_identity_principal_id && r.role_definition_name == "Search Index Data Contributor"])
    error_message = "Each ingestion identity writes its own client's index only (scope: <search>/indexes/<client>)."
  }
  assert {
    condition = (
      azurerm_role_assignment.index["northwind"].role_definition_name == "Search Index Data Reader" &&
      azurerm_role_assignment.index["tailspin"].role_definition_name == "Search Index Data Reader" &&
      azurerm_role_assignment.index["litware"].role_definition_name == "Search Index Data Contributor"
    )
    error_message = "Once a job loads the index, the client's app only reads it."
  }
  assert {
    condition = alltrue(flatten([for k, c in var.clients : [
      [for x in [c.ingest_identity_client_id] : strcontains(output.gateway_policies[k], "<application-id>${x}</application-id>") if x != null],
      [for o, oc in var.clients : !strcontains(output.gateway_policies[k], oc.ingest_identity_client_id) if o != k && oc.ingest_identity_client_id != null],
    ]]))
    error_message = "A client's gateway API admits its own ingestion job, and never another client's."
  }
  assert {
    condition     = azurerm_role_assignment.index_admin["search"].role_definition_name == "Search Service Contributor" && module.ingestion[0].index_admin_job_name == "job-index-admin"
    error_message = "Index definitions on the shared service are managed by the platform's index admin job."
  }
  assert {
    condition     = azurerm_user_assigned_identity.index_admin[0].resource_group_name == azurerm_resource_group.shared.name && length(azurerm_role_assignment.index_admin) == 1
    error_message = "Search Service Contributor goes to the cell's own index admin identity only, never to a client identity."
  }
}
