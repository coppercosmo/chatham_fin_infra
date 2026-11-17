output "job_names" {
  description = "client or tenant code => ingestion job name (start one now with: az containerapp job start)."
  value       = { for k, j in azurerm_container_app_job.this : k => j.name }
}

output "job_ids" {
  value = { for k, j in azurerm_container_app_job.this : k => j.id }
}

output "index_admin_job_name" {
  value = try(azurerm_container_app_job.index_admin[0].name, null)
}

output "settings" {
  description = "The environment each job runs with (no secrets): for tests and for the AKS CronJob, which uses the same contract."
  value = {
    for k, j in azurerm_container_app_job.this : k => {
      for e in j.template[0].container[0].env : e.name => e.value
    }
  }
}
