terraform {
  required_version = ">= 1.9.0"

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }

  # Partial config; values come from terraform/clients/<client>/backend.hcl
  backend "azurerm" {}
}

provider "azurerm" {
  subscription_id     = var.subscription_id
  storage_use_azuread = true # shared keys are disabled everywhere
  # Resource providers are registered by P&T's subscription vending, not by us.
  resource_provider_registrations = "none"

  features {
    key_vault {
      purge_soft_delete_on_destroy = false # never purge client data from Terraform
    }
    cognitive_account {
      purge_soft_delete_on_destroy = false
    }
    resource_group {
      prevent_deletion_if_contains_resources = true
    }
  }
}
