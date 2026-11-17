# Offline tests for the shared ingestion job (mocked provider). The identity each job runs as, and the index it
# writes, are the isolation controls, so they are asserted along with the settings contract.

mock_provider "azurerm" {}

variables {
  resource_group_name          = "rg-cell01-prd-eus2"
  location                     = "eastus2"
  tags                         = {}
  container_app_environment_id = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-cell01-prd-eus2/providers/Microsoft.App/managedEnvironments/cae-cell01"
  image                        = "craiadv.azurecr.io/advisor-ingest@sha256:2222222222222222222222222222222222222222222222222222222222222222"
  registry_server              = "craiadv.azurecr.io"
  jobs = {
    northwind = {
      identity_id        = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-northwind-prd-eus2/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-northwind-prd-eus2-ingest"
      identity_client_id = "a0000000-0000-0000-0000-00000000000c"
      storage_blob_url   = "https://stnorthwind.blob.core.windows.net/"
      search_endpoint    = "https://srch-cell01.search.windows.net"
      search_index       = "northwind"
      openai_endpoint    = "https://apim-cell01.azure-api.net/northwind"
    }
    tailspin = {
      identity_id        = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-tailspin-prd-eus2/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-tailspin-prd-eus2-ingest"
      identity_client_id = "b0000000-0000-0000-0000-00000000000c"
      storage_blob_url   = "https://sttailspin.blob.core.windows.net/"
      search_endpoint    = "https://srch-cell01.search.windows.net"
      search_index       = "tailspin"
      openai_endpoint    = "https://apim-cell01.azure-api.net/tailspin"
      schedule           = "30 1 * * *"
    }
  }
}

run "each_job_runs_as_its_own_identity_on_its_own_index" {
  command = plan

  assert {
    condition     = alltrue([for k, j in azurerm_container_app_job.this : toset(j.identity[0].identity_ids) == toset([var.jobs[k].identity_id]) && j.registry[0].identity == var.jobs[k].identity_id])
    error_message = "A job runs, and pulls its image, as its own client's identity only."
  }
  assert {
    condition     = alltrue([for k, s in output.settings : s.AZURE_CLIENT_ID == var.jobs[k].identity_client_id && s.AZURE_SEARCH_INDEX == k])
    error_message = "Each job authenticates as its own client's identity and writes its own client's index."
  }
  assert {
    condition     = alltrue([for k, s in output.settings : s.AZURE_OPENAI_ENDPOINT == var.jobs[k].openai_endpoint])
    error_message = "Each job embeds through its own client's gateway API."
  }
  assert {
    condition     = alltrue([for s in values(output.settings) : s.INGEST_MODE == "push" && s.MANAGE_INDEX == "false"])
    error_message = "Jobs push by default and can't change index definitions unless the caller allows it."
  }
  assert {
    condition     = alltrue([for s in values(output.settings) : tonumber(s.CHUNK_TOKENS) == 512 && s.AZURE_STORAGE_CONTAINER == "documents"])
    error_message = "Every job gets the same settings contract (chunking, container)."
  }
  assert {
    condition     = azurerm_container_app_job.this["tailspin"].schedule_trigger_config[0].cron_expression == "30 1 * * *" && azurerm_container_app_job.this["northwind"].schedule_trigger_config[0].cron_expression == "0 2 * * *"
    error_message = "Jobs run on a schedule (off-peak by default)."
  }
  assert {
    condition     = length(azurerm_container_app_job.index_admin) == 0
    error_message = "No index admin job unless asked for."
  }
}

run "index_admin_is_a_manual_platform_job" {
  command = plan

  variables {
    index_admin = {
      identity_id        = "/subscriptions/11111111-1111-1111-1111-111111111111/resourceGroups/rg-cell01-prd-eus2/providers/Microsoft.ManagedIdentity/userAssignedIdentities/id-cell01-prd-eus2-index-admin"
      identity_client_id = "f0000000-0000-0000-0000-00000000000f"
      search_endpoint    = "https://srch-cell01.search.windows.net"
      indexes            = ["tailspin", "northwind"]
    }
  }

  assert {
    condition     = length(azurerm_container_app_job.index_admin[0].manual_trigger_config) == 1 && length(azurerm_container_app_job.index_admin[0].schedule_trigger_config) == 0
    error_message = "The index admin job runs when the pipeline starts it, never on a timer."
  }
  assert {
    condition     = contains([for e in azurerm_container_app_job.index_admin[0].template[0].container[0].env : "${e.name}=${e.value}"], "AZURE_SEARCH_INDEXES=northwind,tailspin")
    error_message = "The index admin job manages exactly the listed indexes."
  }
}

run "two_clients_cannot_share_an_identity" {
  command = plan

  variables {
    jobs = {
      northwind = {
        identity_id        = "/subscriptions/1/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/shared"
        identity_client_id = "c0000000-0000-0000-0000-00000000000c"
        storage_blob_url   = "https://stnorthwind.blob.core.windows.net/"
        search_endpoint    = "https://srch-cell01.search.windows.net"
        search_index       = "northwind"
        openai_endpoint    = "https://apim-cell01.azure-api.net/northwind"
      }
      tailspin = {
        identity_id        = "/subscriptions/1/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/shared"
        identity_client_id = "c0000000-0000-0000-0000-00000000000c"
        storage_blob_url   = "https://sttailspin.blob.core.windows.net/"
        search_endpoint    = "https://srch-cell01.search.windows.net"
        search_index       = "tailspin"
        openai_endpoint    = "https://apim-cell01.azure-api.net/tailspin"
      }
    }
  }

  expect_failures = [var.jobs]
}

run "two_jobs_cannot_write_one_index" {
  command = plan

  variables {
    jobs = {
      northwind = {
        identity_id        = "/subscriptions/1/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/a"
        identity_client_id = "a0000000-0000-0000-0000-00000000000c"
        storage_blob_url   = "https://stnorthwind.blob.core.windows.net/"
        search_endpoint    = "https://srch-cell01.search.windows.net"
        search_index       = "shared"
        openai_endpoint    = "https://apim-cell01.azure-api.net/northwind"
      }
      tailspin = {
        identity_id        = "/subscriptions/1/resourceGroups/rg/providers/Microsoft.ManagedIdentity/userAssignedIdentities/b"
        identity_client_id = "b0000000-0000-0000-0000-00000000000c"
        storage_blob_url   = "https://sttailspin.blob.core.windows.net/"
        search_endpoint    = "https://srch-cell01.search.windows.net"
        search_index       = "shared"
        openai_endpoint    = "https://apim-cell01.azure-api.net/tailspin"
      }
    }
  }

  expect_failures = [var.jobs]
}
