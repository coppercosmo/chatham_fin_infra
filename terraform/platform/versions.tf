terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.81"
    }
  }
  backend "azurerm" {}
}

provider "azurerm" {
  subscription_id                 = var.subscription_id
  storage_use_azuread             = true
  resource_provider_registrations = "none"
  features {}
}
