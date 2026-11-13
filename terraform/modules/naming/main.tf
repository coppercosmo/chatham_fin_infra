# Generates CAF-style names so every client stamp is named the same way.
# Pattern: <abbr>-<client>-<env>-<region_short>, with variants for resources that
# disallow dashes or need global uniqueness.

variable "client" {
  type        = string
  description = "Short client code, lowercase letters and digits, 2-12 chars."
  validation {
    condition     = can(regex("^[a-z][a-z0-9]{1,11}$", var.client))
    error_message = "client must be 2-12 lowercase letters/digits, starting with a letter."
  }
}

variable "environment" {
  type    = string
  default = "prd"
  validation {
    condition     = contains(["dev", "tst", "prd"], var.environment)
    error_message = "environment must be dev, tst, or prd."
  }
}

variable "location" {
  type = string
}

variable "unique_seed" {
  type        = string
  description = "Stable seed (e.g. subscription ID) used for a short suffix on globally unique names."
}

locals {
  region_short = lookup({
    eastus         = "eus"
    eastus2        = "eus2"
    centralus      = "cus"
    westus3        = "wus3"
    northcentralus = "ncus"
    uksouth        = "uks"
    westeurope     = "weu"
    swedencentral  = "sdc"
  }, var.location, substr(var.location, 0, 6))

  base   = "${var.client}-${var.environment}-${local.region_short}"
  suffix = substr(sha1(var.unique_seed), 0, 4)
  flat   = "${var.client}${var.environment}${local.region_short}${local.suffix}"
}

output "base" { value = local.base }
output "region_short" { value = local.region_short }

output "names" {
  value = {
    resource_group            = "rg-${local.base}"
    vnet                      = "vnet-${local.base}"
    nsg_apps                  = "nsg-${local.base}-apps"
    nsg_pe                    = "nsg-${local.base}-pe"
    route_table               = "rt-${local.base}"
    key_vault                 = substr("kv-${local.base}-${local.suffix}", 0, 24)
    openai                    = "oai-${local.base}-${local.suffix}"
    search                    = "srch-${local.base}-${local.suffix}"
    storage_account           = substr("st${local.flat}", 0, 24)
    log_analytics             = "log-${local.base}"
    app_insights              = "appi-${local.base}"
    container_app_environment = "cae-${local.base}"
    container_app_infra_rg    = "rg-${local.base}-cae-infra"
    container_app_api         = "ca-${var.client}-api"
    identity_app              = "id-${local.base}-app"
    budget                    = "budget-${local.base}"
  }
}
