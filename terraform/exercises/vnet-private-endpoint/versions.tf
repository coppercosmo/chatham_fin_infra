terraform {
  required_version = ">= 1.9.0"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.0" # any 4.x: a root module pins the major version, the lock file pins the exact build
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id # required since azurerm 4.0
  storage_use_azuread = true                # shared keys are off, so the provider must use Entra ID
}
