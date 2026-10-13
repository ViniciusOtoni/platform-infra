terraform {
  required_version = ">= 1.9"

  backend "azurerm" {}

  required_providers {
    databricks = {
      source  = "databricks/databricks"
      version = "~> 1.90"
    }
  }
}

# Auth: sessão az CLI (local: `az login`; CI: azure/login com OIDC).
provider "databricks" {
  host                        = data.terraform_remote_state.core.outputs.databricks_workspace_url
  azure_workspace_resource_id = data.terraform_remote_state.core.outputs.databricks_workspace_resource_id
  auth_type                   = "azure-cli"
}
