# Scheduled document ingestion (ADR 0015): read new or changed files from the client's storage, split them into
# chunks, embed each chunk through the AI gateway and write chunk text, vector and source to the client's index.
# Deleted files have their chunks removed. Same job design and settings contract in all three tiers.

resource "azurerm_container_app_job" "this" {
  for_each                     = var.jobs
  name                         = "job-${each.key}-ingest"
  location                     = var.location
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  replica_timeout_in_seconds   = var.replica_timeout_in_seconds
  replica_retry_limit          = 1
  workload_profile_name        = var.workload_profile_name
  tags                         = merge(var.tags, { client = each.key, workload = "ingestion" })

  # The job's own identity, never the app's: background work has no signed-in user, and keeping it separate
  # means the app can be read-only on the index.
  identity {
    type         = "UserAssigned"
    identity_ids = [each.value.identity_id]
  }

  dynamic "registry" {
    for_each = var.registry_server == null ? [] : [1]
    content {
      server   = var.registry_server
      identity = each.value.identity_id
    }
  }

  schedule_trigger_config {
    cron_expression          = each.value.schedule
    parallelism              = 1
    replica_completion_count = 1
  }

  template {
    container {
      name   = "ingest"
      image  = var.image
      cpu    = 0.5
      memory = "1Gi"

      dynamic "env" {
        for_each = {
          AZURE_CLIENT_ID         = each.value.identity_client_id
          CLIENT_CODE             = each.key # informational: the identity can reach only this client's data anyway
          INGEST_MODE             = each.value.mode
          MANAGE_INDEX            = tostring(each.value.manage_index)
          AZURE_STORAGE_BLOB_URL  = each.value.storage_blob_url
          AZURE_STORAGE_CONTAINER = each.value.storage_container
          AZURE_SEARCH_ENDPOINT   = each.value.search_endpoint
          AZURE_SEARCH_INDEX      = each.value.search_index
          AZURE_OPENAI_ENDPOINT   = each.value.openai_endpoint
          EMBEDDING_DEPLOYMENT    = each.value.embedding_deployment
          CHUNK_TOKENS            = tostring(var.chunking.tokens)
          CHUNK_OVERLAP_TOKENS    = tostring(var.chunking.overlap_tokens)
        }
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }
}

# Shared tiers: one job that owns the index definitions (fields, vector profile, semantic configuration).
resource "azurerm_container_app_job" "index_admin" {
  count                        = var.index_admin == null ? 0 : 1
  name                         = "job-index-admin"
  location                     = var.location
  resource_group_name          = var.resource_group_name
  container_app_environment_id = var.container_app_environment_id
  replica_timeout_in_seconds   = 900
  replica_retry_limit          = 1
  workload_profile_name        = var.workload_profile_name
  tags                         = merge(var.tags, { workload = "search-index-admin" })

  identity {
    type         = "UserAssigned"
    identity_ids = [var.index_admin.identity_id]
  }

  dynamic "registry" {
    for_each = var.registry_server == null ? [] : [1]
    content {
      server   = var.registry_server
      identity = var.index_admin.identity_id
    }
  }

  # Started by the pipeline (az containerapp job start) after onboarding or a schema change, never on a timer.
  manual_trigger_config {
    parallelism              = 1
    replica_completion_count = 1
  }

  template {
    container {
      name   = "index-admin"
      image  = var.image
      cpu    = 0.25
      memory = "0.5Gi"

      dynamic "env" {
        for_each = {
          AZURE_CLIENT_ID       = var.index_admin.identity_client_id
          INGEST_MODE           = "index-admin"
          AZURE_SEARCH_ENDPOINT = var.index_admin.search_endpoint
          AZURE_SEARCH_INDEXES  = join(",", sort(var.index_admin.indexes))
        }
        content {
          name  = env.key
          value = env.value
        }
      }
    }
  }
}
