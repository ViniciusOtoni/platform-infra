terraform {
  required_version = ">= 1.9"

  backend "azurerm" {}

  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.40"
    }
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.90"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}

# Auth: sessão az CLI (local: `az login`; CI: azure/login com OIDC).
provider "databricks" {
  host                        = local.foundation.databricks_workspace_url
  azure_workspace_resource_id = local.foundation.databricks_workspace_resource_id
  auth_type                   = "azure-cli"
}
