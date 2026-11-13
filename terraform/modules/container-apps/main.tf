resource "azurerm_container_app_environment" "this" {
  name                               = var.environment_name
  location                           = var.location
  resource_group_name                = var.resource_group_name
  log_analytics_workspace_id         = var.log_analytics_workspace_id
  infrastructure_subnet_id           = var.infrastructure_subnet_id
  infrastructure_resource_group_name = var.infrastructure_resource_group_name
  internal_load_balancer_enabled     = true # no public IP (ADR 0003, 0005)
  zone_redundancy_enabled            = var.zone_redundant
  tags                               = var.tags

  workload_profile {
    name                  = "Consumption"
    workload_profile_type = "Consumption"
  }
}

# Internal environments need DNS for *.<default_domain> -> static IP, resolvable from the spoke.
resource "azurerm_private_dns_zone" "env" {
  name                = azurerm_container_app_environment.this.default_domain
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

resource "azurerm_private_dns_a_record" "wildcard" {
  name                = "*"
  zone_name           = azurerm_private_dns_zone.env.name
  resource_group_name = var.resource_group_name
  ttl                 = 300
  records             = [azurerm_container_app_environment.this.static_ip_address]
}

resource "azurerm_private_dns_zone_virtual_network_link" "env" {
  name                  = "link-spoke"
  resource_group_name   = var.resource_group_name
  private_dns_zone_name = azurerm_private_dns_zone.env.name
  virtual_network_id    = var.vnet_id
  registration_enabled  = false
  tags                  = var.tags
}

resource "azurerm_container_app" "api" {
  name                         = var.app_name
  container_app_environment_id = azurerm_container_app_environment.this.id
  resource_group_name          = var.resource_group_name
  revision_mode                = "Single"
  workload_profile_name        = "Consumption"
  tags                         = var.tags

  identity {
    type         = "UserAssigned"
    identity_ids = [var.identity_id]
  }

  dynamic "registry" {
    for_each = var.registry_server == null ? [] : [1]
    content {
      server   = var.registry_server
      identity = var.identity_id
    }
  }

  secret {
    name  = "appinsights-connection-string"
    value = var.app_insights_connection_string
  }

  ingress {
    external_enabled = true # "external" to the environment = reachable on the VNet; env itself is internal
    target_port      = var.target_port
    transport        = "auto"
    traffic_weight {
      latest_revision = true
      percentage      = 100
    }
  }

  template {
    min_replicas = var.min_replicas
    max_replicas = var.max_replicas

    container {
      name   = "api"
      image  = var.image
      cpu    = 0.5
      memory = "1Gi"

      env {
        name  = "AZURE_CLIENT_ID" # tells DefaultAzureCredential which managed identity to use
        value = var.identity_client_id
      }

      env {
        name        = "APPLICATIONINSIGHTS_CONNECTION_STRING"
        secret_name = "appinsights-connection-string"
      }

      dynamic "env" {
        for_each = var.env
        content {
          name  = env.key
          value = env.value
        }
      }

      liveness_probe {
        transport = "HTTP"
        port      = var.target_port
        path      = "/"
      }
    }
  }
}
