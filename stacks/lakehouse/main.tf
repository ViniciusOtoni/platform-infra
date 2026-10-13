# Objetos compartilhados do Unity Catalog. Objetos por domínio ficam no stack "domains".

data "terraform_remote_state" "core" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.tfstate_resource_group_name
    storage_account_name = var.tfstate_storage_account_name
    container_name       = "tfstate"
    key                  = "core/${var.environment}.tfstate"
    use_azuread_auth     = true
  }
}

locals {
  core          = data.terraform_remote_state.core.outputs
  lakehouse_url = "abfss://${local.core.lakehouse_container_name}@${local.core.storage_account_name}.dfs.core.windows.net/"
}

# Credencial do UC baseada na managed identity do Access Connector (sem segredos).
resource "databricks_storage_credential" "lake" {
  name    = "edp_${var.environment}_lake"
  comment = "Access Connector da plataforma (managed identity). Gerenciado por platform-infra."

  azure_managed_identity {
    access_connector_id = local.core.databricks_access_connector_id
  }
}

# Raiz do managed storage dos catálogos de domínio (<dominio>_<env>).
resource "databricks_external_location" "lakehouse" {
  name            = "edp_${var.environment}_lakehouse"
  url             = local.lakehouse_url
  credential_name = databricks_storage_credential.lake.name
  comment         = "Managed storage dos catálogos de domínio. Gerenciado por platform-infra."
}

# SP usado pelos pipelines de domínio (bundle deploy / run_as dos jobs).
resource "databricks_service_principal" "deployer" {
  application_id        = var.deployer_client_id
  display_name          = "gh-edp-deployer"
  workspace_access      = true
  databricks_sql_access = true
}
