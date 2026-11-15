# Private, Entra-integrated AKS cluster for ONE client, in that client's subscription (ADR 0011).
# A dedicated cluster per client keeps ADR 0001 intact: no shared control plane, kernel, node,
# identity or network policy between clients.

locals {
  landing_zone = var.egress_via_hub_firewall
  byo_dns_zone = var.private_dns_zone_id != "System"
}

# ---------------------------------------------------------------- control-plane identity
# User-assigned so its permissions exist BEFORE the cluster is created (BYO subnet / route table / DNS).
resource "azurerm_user_assigned_identity" "control_plane" {
  name                = var.control_plane_identity_name
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Kubelet identity is also user-assigned, so AcrPull exists before the first node pulls an image.
resource "azurerm_user_assigned_identity" "kubelet" {
  name                = "${var.control_plane_identity_name}-kubelet"
  location            = var.location
  resource_group_name = var.resource_group_name
  tags                = var.tags
}

# Required for BYO kubelet identity: the control plane assigns it to the node VMSS.
resource "azurerm_role_assignment" "cp_kubelet_operator" {
  scope                = azurerm_user_assigned_identity.kubelet.id
  role_definition_name = "Managed Identity Operator"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "cp_subnet" {
  scope                = var.subnet_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "cp_route_table" {
  count                = local.landing_zone ? 1 : 0
  scope                = var.route_table_id
  role_definition_name = "Network Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "cp_dns" {
  count                = local.byo_dns_zone ? 1 : 0
  scope                = var.private_dns_zone_id
  role_definition_name = "Private DNS Zone Contributor"
  principal_id         = azurerm_user_assigned_identity.control_plane.principal_id
  principal_type       = "ServicePrincipal"
}

# ---------------------------------------------------------------- cluster
resource "azurerm_kubernetes_cluster" "this" {
  #checkov:skip=CKV_AZURE_117:Disk encryption set (CMK) is a per-client contract option, same as storage/AOAI (README known gaps). Host encryption is on.
  #checkov:skip=CKV_AZURE_6:Authorized IP ranges do not apply to a private cluster; the API server has no public endpoint.
  name                       = var.name
  location                   = var.location
  resource_group_name        = var.resource_group_name
  node_resource_group        = var.node_resource_group_name
  dns_prefix_private_cluster = var.name
  kubernetes_version         = var.kubernetes_version
  sku_tier                   = "Standard" # financially backed API server SLA
  tags                       = var.tags

  # ---- access: private API, Entra ID only, Azure RBAC for Kubernetes authorization
  private_cluster_enabled             = true
  private_dns_zone_id                 = var.private_dns_zone_id
  private_cluster_public_fqdn_enabled = false
  local_account_disabled              = true
  role_based_access_control_enabled   = true

  azure_active_directory_role_based_access_control {
    tenant_id              = var.tenant_id
    azure_rbac_enabled     = true
    admin_group_object_ids = var.admin_group_object_ids
  }

  # ---- workload identity: pods federate to Entra managed identities (no secrets in pods)
  oidc_issuer_enabled       = true
  workload_identity_enabled = true

  # ---- guardrails: P&T's Azure Policy definitions are enforced inside the cluster via Gatekeeper
  azure_policy_enabled = true

  # ---- secrets from the client Key Vault, mounted via CSI, rotated automatically
  key_vault_secrets_provider {
    secret_rotation_enabled  = true
    secret_rotation_interval = "2m"
  }

  # ---- managed NGINX ingress (app routing add-on); exposed on an internal LB only, see kubernetes/
  web_app_routing {
    dns_zone_ids = []
  }

  # ---- lifecycle: patch-level auto upgrades, weekly node image, stale image cleanup
  automatic_upgrade_channel    = "patch"
  node_os_upgrade_channel      = "NodeImage"
  image_cleaner_enabled        = true
  image_cleaner_interval_hours = 48

  maintenance_window_auto_upgrade {
    frequency   = "Weekly"
    interval    = 1
    duration    = 4
    day_of_week = "Sunday"
    start_time  = "02:00"
    utc_offset  = "-05:00"
  }

  # ---- network: CNI Overlay + Cilium dataplane and network policy
  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
    network_data_plane  = "cilium"
    network_policy      = "cilium"
    load_balancer_sku   = "standard"
    outbound_type       = local.landing_zone ? "userDefinedRouting" : "loadBalancer"
    pod_cidr            = "192.168.0.0/16" # overlay: not routable outside the cluster, can repeat per client
    service_cidr        = "172.16.0.0/16"
    dns_service_ip      = "172.16.0.10"
  }

  oms_agent {
    log_analytics_workspace_id      = var.log_analytics_workspace_id
    msi_auth_for_monitoring_enabled = true
  }

  identity {
    type         = "UserAssigned"
    identity_ids = [azurerm_user_assigned_identity.control_plane.id]
  }

  kubelet_identity {
    user_assigned_identity_id = azurerm_user_assigned_identity.kubelet.id
    client_id                 = azurerm_user_assigned_identity.kubelet.client_id
    object_id                 = azurerm_user_assigned_identity.kubelet.principal_id
  }

  default_node_pool {
    name                         = "system"
    vm_size                      = var.system_pool.vm_size
    vnet_subnet_id               = var.subnet_id
    zones                        = var.zones
    auto_scaling_enabled         = true
    min_count                    = var.system_pool.min_count
    max_count                    = var.system_pool.max_count
    max_pods                     = 110
    only_critical_addons_enabled = true # system pods only; app pods go to the user pool
    host_encryption_enabled      = true
    os_disk_type                 = "Ephemeral"
    os_disk_size_gb              = 128
    os_sku                       = "AzureLinux"
    temporary_name_for_rotation  = "systemtmp"
    tags                         = var.tags

    upgrade_settings {
      max_surge = "33%"
    }
  }

  depends_on = [
    azurerm_role_assignment.cp_kubelet_operator,
    azurerm_role_assignment.kubelet_acr,
    azurerm_role_assignment.cp_subnet,
    azurerm_role_assignment.cp_route_table,
    azurerm_role_assignment.cp_dns,
  ]

  lifecycle {
    ignore_changes = [
      default_node_pool[0].node_count, # owned by the autoscaler
      kubernetes_version,              # owned by the auto-upgrade channel
    ]
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "user" {
  name                    = "user"
  kubernetes_cluster_id   = azurerm_kubernetes_cluster.this.id
  mode                    = "User"
  vm_size                 = var.user_pool.vm_size
  vnet_subnet_id          = var.subnet_id
  zones                   = var.zones
  auto_scaling_enabled    = true
  min_count               = var.user_pool.min_count
  max_count               = var.user_pool.max_count
  max_pods                = 110
  host_encryption_enabled = true
  os_disk_type            = "Ephemeral"
  os_disk_size_gb         = 128
  os_sku                  = "AzureLinux"
  tags                    = var.tags

  upgrade_settings {
    max_surge = "33%"
  }

  lifecycle {
    ignore_changes = [node_count]
  }
}

resource "azurerm_kubernetes_cluster_node_pool" "gpu" {
  count                   = var.gpu_pool == null ? 0 : 1
  name                    = "gpu"
  kubernetes_cluster_id   = azurerm_kubernetes_cluster.this.id
  mode                    = "User"
  vm_size                 = var.gpu_pool.vm_size
  vnet_subnet_id          = var.subnet_id
  zones                   = var.zones
  auto_scaling_enabled    = true
  min_count               = var.gpu_pool.min_count
  max_count               = var.gpu_pool.max_count
  max_pods                = 50
  host_encryption_enabled = true
  os_disk_type            = "Ephemeral"
  os_sku                  = "Ubuntu" # NVIDIA driver support
  node_taints             = ["sku=gpu:NoSchedule"]
  node_labels             = { "workload" = "gpu" }
  tags                    = var.tags

  lifecycle {
    ignore_changes = [node_count]
  }
}

# ---------------------------------------------------------------- access for humans and images
resource "azurerm_role_assignment" "readers" {
  count                = var.reader_group_object_id == null ? 0 : 1
  scope                = azurerm_kubernetes_cluster.this.id
  role_definition_name = "Azure Kubernetes Service RBAC Reader"
  principal_id         = var.reader_group_object_id
  principal_type       = "Group"
}

# App routing add-on (managed NGINX) pulls the backend TLS certificate from the client's vault,
# so App Gateway -> NGINX is TLS with the same certificate the listener uses.
resource "azurerm_role_assignment" "app_routing_kv" {
  scope                = var.key_vault_id
  role_definition_name = "Key Vault Secrets User"
  principal_id         = azurerm_kubernetes_cluster.this.web_app_routing[0].web_app_routing_identity[0].object_id
  principal_type       = "ServicePrincipal"
}

resource "azurerm_role_assignment" "kubelet_acr" {
  count                            = var.acr_id == null ? 0 : 1
  scope                            = var.acr_id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_user_assigned_identity.kubelet.principal_id
  principal_type                   = "ServicePrincipal"
  skip_service_principal_aad_check = true
}

# ---------------------------------------------------------------- workload identity federation
# The app's existing managed identity (same one Container Apps would use) trusts tokens issued
# by THIS cluster for ONE namespace/service account. Another client's cluster can't use it.
resource "azurerm_federated_identity_credential" "workload" {
  for_each  = var.workload_identities
  name      = "aks-${each.value.namespace}-${each.value.service_account}"
  parent_id = each.value.identity_id
  audience  = ["api://AzureADTokenExchange"]
  issuer    = azurerm_kubernetes_cluster.this.oidc_issuer_url
  subject   = "system:serviceaccount:${each.value.namespace}:${each.value.service_account}"
}

resource "azurerm_monitor_diagnostic_setting" "aks" {
  name                       = "diag-to-client-law"
  target_resource_id         = azurerm_kubernetes_cluster.this.id
  log_analytics_workspace_id = var.log_analytics_workspace_id

  enabled_log {
    category_group = "audit" # kube-audit, kube-audit-admin, guard: who did what in the cluster
  }
}
