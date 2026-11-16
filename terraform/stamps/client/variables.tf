# ---------- Identity of the client and where it runs
variable "client" {
  type        = string
  description = "Short client code, e.g. acme. Drives all names."
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,11}$", var.client))
    error_message = "client must be 2-12 lowercase letters/digits, starting with a letter."
  }
}

variable "environment" {
  type    = string
  default = "prd"
}

variable "location" {
  type    = string
  default = "eastus2"
}

variable "subscription_id" {
  type        = string
  description = "The client's dedicated subscription (ADR 0001)."
}

variable "tags" {
  type        = map(string)
  default     = {}
  description = "Extra tags. Required tags (client, data_classification, cost_center, owner) are added automatically."
}

variable "data_classification" {
  type    = string
  default = "confidential"
}

variable "cost_center" { type = string }
variable "owner_email" { type = string }

# ---------- Connectivity (ADR 0002, 0003)
variable "connectivity_mode" {
  type        = string
  default     = "standalone"
  description = "landing_zone: peer to P&T hub, DNS records via P&T policy. standalone: self-contained (demo/dev)."
  validation {
    condition     = contains(["landing_zone", "standalone"], var.connectivity_mode)
    error_message = "connectivity_mode must be landing_zone or standalone."
  }
}

variable "address_space" {
  type        = string
  description = "Spoke CIDR from P&T IPAM, /22 recommended."
}

variable "hub" {
  type = object({
    vnet_id             = string
    firewall_private_ip = string
    dns_servers         = list(string)
    # true once P&T's hub-side peering allows gateway transit for this spoke (onboarding step 3 for
    # VPN/ExpressRoute clients, ADR 0013). Until then the client's network can't reach the spoke.
    gateway_transit = optional(bool, false)
  })
  default = null
}

# ---------- Client network connectivity (ADR 0013)
# How the CLIENT's own network reaches this environment. Separate from connectivity_mode, which is
# how this spoke attaches to Azure plumbing (P&T hub or standalone).
variable "client_connectivity" {
  description = <<-EOT
    none:         no private path from the client's network (internet users with a public frontend, or
                  Chatham-only access).
    privatelink:  preferred for clients already on Azure. The client creates a private endpoint in THEIR
                  subscription that connects to this client's App Gateway. No routing, no shared hub, IP
                  overlap doesn't matter. Works in standalone and landing-zone mode.
    vpn:          site-to-site IPsec tunnel from the client's firewall to P&T's hub VPN gateway.
    expressroute: the client's ExpressRoute circuit linked to P&T's hub ExpressRoute gateway.

    on_prem_prefixes (vpn/expressroute): the client's ranges AS SEEN IN AZURE (after any NAT). They become
    the firewall rule, the App Gateway NSG and WAF allow-list, and the return routes. Must not overlap
    this spoke or any other client.
  EOT
  type = object({
    type             = string
    on_prem_prefixes = optional(list(string), [])

    vpn = optional(object({
      device_public_ip = string # the client's VPN device
      # Static 1:1 NAT for a client whose real range overlaps someone else's. client_prefix is what the
      # client uses at home; azure_prefix is the unique range (from P&T IPAM, e.g. 100.64.0.0/10) that it
      # becomes inside Azure, and must be listed in on_prem_prefixes.
      nat = optional(list(object({
        client_prefix = string
        azure_prefix  = string
      })), [])
    }))

    expressroute = optional(object({
      circuit_id     = string # the client's circuit; they issue an authorization key for P&T's gateway
      routing_weight = optional(number, 0)
    }))

    private_link = optional(object({
      # The client's own subscriptions whose private endpoints we approve. Anything else is rejected.
      consumer_subscription_ids = list(string)
    }))
  })
  default = { type = "none" }

  validation {
    condition     = contains(["none", "privatelink", "vpn", "expressroute"], var.client_connectivity.type)
    error_message = "client_connectivity.type must be none, privatelink, vpn or expressroute."
  }
  validation {
    condition = !contains(["vpn", "expressroute"], var.client_connectivity.type) || (
      length(var.client_connectivity.on_prem_prefixes) > 0 &&
      alltrue([for p in var.client_connectivity.on_prem_prefixes : can(cidrhost(p, 0))])
    )
    error_message = "vpn and expressroute need on_prem_prefixes: the client's network ranges as CIDRs."
  }
  validation {
    condition = alltrue([
      var.client_connectivity.type != "vpn" || var.client_connectivity.vpn != null,
      var.client_connectivity.type != "expressroute" || var.client_connectivity.expressroute != null,
      var.client_connectivity.type != "privatelink" || var.client_connectivity.private_link != null,
    ])
    error_message = "Set the block that matches client_connectivity.type (vpn, expressroute or private_link)."
  }
  validation {
    condition = alltrue([
      for m in try(var.client_connectivity.vpn.nat, []) :
      contains(var.client_connectivity.on_prem_prefixes, m.azure_prefix) &&
      split("/", m.azure_prefix)[1] == split("/", m.client_prefix)[1]
    ])
    error_message = "Each vpn.nat azure_prefix must be listed in on_prem_prefixes and be the same size as its client_prefix (static 1:1 NAT)."
  }
}

# ---------- Access (P&T-owned Entra groups, ADR 0004)
variable "reader_group_object_id" {
  type        = string
  default     = null
  description = "P&T-owned group with standing Reader on the client RG. Operators get write via PIM, outside Terraform."
}

# ---------- AI (ADR 0006)
variable "model_deployments" {
  type = map(object({
    model_name    = string
    model_version = string
    sku           = optional(string, "DataZoneStandard")
    capacity      = optional(number, 10)
  }))
  default = {
    "chat" = {
      model_name    = "gpt-4o"
      model_version = "2024-11-20"
      capacity      = 30
    }
    "embeddings" = {
      model_name    = "text-embedding-3-large"
      model_version = "1"
      capacity      = 30
    }
  }
}

variable "enable_search" {
  type    = bool
  default = true
}

variable "search_replica_count" {
  type        = number
  default     = 3
  description = "3 meets the AI Search read/write SLA. Use 1 for internal or non-production clients."
}

# ---------- Compute (ADR 0005, 0011)
variable "compute_platform" {
  type        = string
  default     = "container_apps"
  description = "container_apps (default) or aks (dedicated private cluster for this client)."
  validation {
    condition     = contains(["container_apps", "aks"], var.compute_platform)
    error_message = "compute_platform must be container_apps or aks."
  }
}

variable "aks" {
  description = "AKS settings, used when compute_platform = aks."
  type = object({
    kubernetes_version     = optional(string)
    private_dns_zone_id    = optional(string, "System")
    admin_group_object_ids = optional(list(string), [])
    app_namespace          = optional(string, "advisor")
    app_service_account    = optional(string, "advisor-api")
    system_pool = optional(object({
      vm_size   = optional(string, "Standard_D4ds_v5")
      min_count = optional(number, 3)
      max_count = optional(number, 5)
    }), {})
    user_pool = optional(object({
      vm_size   = optional(string, "Standard_D8ds_v5")
      min_count = optional(number, 2)
      max_count = optional(number, 10)
    }), {})
    gpu_pool = optional(object({
      vm_size   = optional(string, "Standard_NC24ads_A100_v4")
      min_count = optional(number, 0)
      max_count = optional(number, 2)
    }))
  })
  default = {}
}

# ---------- AI gateway (ADR 0012)
variable "ai_gateway" {
  description = "Azure API Management AI gateway between the app and Azure OpenAI. null = app calls AOAI directly."
  type = object({
    sku_name                 = optional(string, "Developer_1")
    tokens_per_minute        = optional(number, 50000)
    monthly_token_quota      = optional(number, 0)
    enable_content_safety    = optional(bool, false)
    log_request_bodies_bytes = optional(number, 0)
    additional_backends = optional(list(object({
      name        = string
      url         = string
      resource_id = string
    })), [])
  })
  default = null
}

# ---------- Ingress (ADR 0010)
variable "ingress" {
  description = "Per-client Application Gateway WAF_v2. null = no ingress (internal-only/demo)."
  type = object({
    host_name                   = string
    certificate_secret_id       = string # versionless Key Vault secret ID in THIS client's vault
    frontend_mode               = optional(string, "private")
    allowed_source_prefixes     = optional(list(string), ["VirtualNetwork"])
    allowed_client_cidrs        = optional(list(string), [])
    waf_mode                    = optional(string, "Prevention")
    waf_prompt_field_exclusions = optional(list(string), ["messages", "prompt", "input"])
    rate_limit_per_minute       = optional(number, 600)
    min_capacity                = optional(number, 1)
    max_capacity                = optional(number, 5)
    health_probe_path           = optional(string, "/healthz")
  })
  default = null
}

# ---------- App (ADR 0005, 0008)
variable "app_image" {
  type        = string
  default     = "mcr.microsoft.com/k8se/quickstart:latest"
  description = "Promoted by ring. Pin by digest for real clients, e.g. <acr>.azurecr.io/advisor-api@sha256:..."
}

variable "acr" {
  type = object({
    id           = string
    login_server = string
  })
  default     = null
  description = "Shared platform ACR. null when using a public image (demo)."
}

variable "zone_redundant" {
  type    = bool
  default = true
}

# ---------- Ops (ADR 0009)
variable "log_retention_days" {
  type    = number
  default = 90
}

variable "monthly_budget_usd" {
  type    = number
  default = 2000
}

variable "budget_contact_emails" {
  type    = list(string)
  default = []
}

variable "enable_locks" {
  type        = bool
  default     = true
  description = "CanNotDelete locks on data-bearing resources. Set false only when offboarding."
}
