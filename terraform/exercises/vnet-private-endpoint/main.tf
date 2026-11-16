# Interview exercise (docs/interview/practice/mock-technical-test.md, part B): from scratch, no modules.
# A VNet with a workload subnet and a private-endpoint subnet, a storage account and a Key Vault with
# public access off, and one private endpoint each, registered in private DNS zones linked to the VNet.
#
#   snet-workload (/24) --443--> snet-pe (/24): pe-blob, pe-vault --Private Link--> storage, Key Vault
#   privatelink.blob.core.windows.net / privatelink.vaultcore.azure.net, linked to the VNet

data "azurerm_client_config" "current" {}

locals {
  suffix = substr(md5("${var.subscription_id}/${var.prefix}"), 0, 6) # stable, unique enough for global names

  subnets = {
    workload = cidrsubnet(var.address_space, 2, 0) # x.x.0.0/24
    pe       = cidrsubnet(var.address_space, 2, 1) # x.x.1.0/24
  }

  # One entry per private endpoint. Keys are static strings, so for_each knows them at plan time even
  # though the resource IDs inside are only known after apply.
  endpoints = {
    blob = {
      resource_id = azurerm_storage_account.this.id
      subresource = "blob"
      zone        = "privatelink.blob.core.windows.net"
    }
    vault = {
      resource_id = azurerm_key_vault.this.id
      subresource = "vault"
      zone        = "privatelink.vaultcore.azure.net"
    }
  }
  zones = toset([for e in values(local.endpoints) : e.zone])
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${var.prefix}"
  location = var.location
  tags     = var.tags
}

# ------------------------------------------------------------------ network
resource "azurerm_virtual_network" "this" {
  name                = "vnet-${var.prefix}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  address_space       = [var.address_space]
  tags                = var.tags
}

resource "azurerm_subnet" "this" {
  for_each             = local.subnets
  name                 = "snet-${each.key}"
  resource_group_name  = azurerm_resource_group.this.name
  virtual_network_name = azurerm_virtual_network.this.name
  address_prefixes     = [each.value]

  # Make NSG rules apply to private endpoints too (they're ignored by default).
  private_endpoint_network_policies = each.key == "pe" ? "Enabled" : "Disabled"
}

resource "azurerm_network_security_group" "pe" {
  name                = "nsg-${var.prefix}-pe"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags

  security_rule {
    name                       = "allow-workload-https"
    priority                   = 100
    direction                  = "Inbound"
    access                     = "Allow"
    protocol                   = "Tcp"
    source_port_range          = "*"
    destination_port_range     = "443"
    source_address_prefix      = local.subnets.workload
    destination_address_prefix = local.subnets.pe
  }

  security_rule {
    name                       = "deny-all-inbound"
    priority                   = 4096
    direction                  = "Inbound"
    access                     = "Deny"
    protocol                   = "*"
    source_port_range          = "*"
    destination_port_range     = "*"
    source_address_prefix      = "*"
    destination_address_prefix = "*"
  }
}

# Every subnet gets an NSG (landing-zone policies usually require it). The workload one keeps Azure's
# default rules: VNet traffic in, nothing from the internet.
resource "azurerm_network_security_group" "workload" {
  name                = "nsg-${var.prefix}-workload"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_subnet_network_security_group_association" "this" {
  for_each                  = { workload = azurerm_network_security_group.workload.id, pe = azurerm_network_security_group.pe.id }
  subnet_id                 = azurerm_subnet.this[each.key].id
  network_security_group_id = each.value
}

# ------------------------------------------------------------------ private DNS
# Without the zone AND the VNet link, the endpoint exists but names still resolve to the public IP.
resource "azurerm_private_dns_zone" "this" {
  for_each            = local.zones
  name                = each.value
  resource_group_name = azurerm_resource_group.this.name
  tags                = var.tags
}

resource "azurerm_private_dns_zone_virtual_network_link" "this" {
  for_each              = azurerm_private_dns_zone.this
  name                  = "link-${azurerm_virtual_network.this.name}"
  resource_group_name   = azurerm_resource_group.this.name
  private_dns_zone_name = each.value.name
  virtual_network_id    = azurerm_virtual_network.this.id
  registration_enabled  = false # only VMs auto-register; endpoints use zone groups
  tags                  = var.tags
}

# ------------------------------------------------------------------ PaaS, private and keyless
resource "azurerm_storage_account" "this" {
  #checkov:skip=CKV2_AZURE_1:Exercise scope: Microsoft-managed keys. CMK is covered in docs/interview/deep-dives/data-isolation-for-ai.md.
  #checkov:skip=CKV_AZURE_206:Exercise scope: LRS keeps it cheap. Production stamps use ZRS/GZRS (DR deep dive).
  #checkov:skip=CKV_AZURE_33:No queues in this exercise.
  #checkov:skip=CKV2_AZURE_21:Blob read logging is out of scope for the exercise.
  name                            = "st${var.prefix}${local.suffix}"
  location                        = var.location
  resource_group_name             = azurerm_resource_group.this.name
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  public_network_access_enabled   = false
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  tags                            = var.tags

  network_rules {
    default_action = "Deny"
    bypass         = ["AzureServices"]
  }

  blob_properties {
    delete_retention_policy {
      days = 7
    }
  }

  sas_policy {
    expiration_period = "01.00:00:00"
  }
}

resource "azurerm_key_vault" "this" {
  name                          = "kv-${var.prefix}-${local.suffix}"
  location                      = var.location
  resource_group_name           = azurerm_resource_group.this.name
  tenant_id                     = data.azurerm_client_config.current.tenant_id
  sku_name                      = "standard"
  rbac_authorization_enabled    = true
  purge_protection_enabled      = true
  soft_delete_retention_days    = 7
  public_network_access_enabled = false
  tags                          = var.tags

  network_acls {
    default_action = "Deny"
    bypass         = "AzureServices"
  }
}

# ------------------------------------------------------------------ private endpoints
resource "azurerm_private_endpoint" "this" {
  for_each            = local.endpoints
  name                = "pe-${var.prefix}-${each.key}"
  location            = var.location
  resource_group_name = azurerm_resource_group.this.name
  subnet_id           = azurerm_subnet.this["pe"].id
  tags                = var.tags

  private_service_connection {
    name                           = "psc-${each.key}"
    private_connection_resource_id = each.value.resource_id
    subresource_names              = [each.value.subresource]
    is_manual_connection           = false
  }

  # Writes the A record (e.g. st...privatelink.blob.core.windows.net -> 10.50.1.4) for us.
  private_dns_zone_group {
    name                 = "default"
    private_dns_zone_ids = [azurerm_private_dns_zone.this[each.value.zone].id]
  }

  depends_on = [azurerm_subnet_network_security_group_association.this]
}
