# Lakehouse (PERSISTENTE): objetos compartilhados do Unity Catalog + parte de dados de cada domínio.

data "terraform_remote_state" "foundation" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.tfstate_resource_group_name
    storage_account_name = var.tfstate_storage_account_name
    container_name       = "tfstate"
    key                  = "foundation/${var.environment}.tfstate"
    use_azuread_auth     = true
  }
}

locals {
  foundation    = data.terraform_remote_state.foundation.outputs
  lakehouse_url = "abfss://${local.foundation.lakehouse_container_name}@${local.foundation.storage_account_name}.dfs.core.windows.net/"
  # Fonte única dos domínios (compartilhada com o stack runtime).
  domains = yamldecode(file("${path.module}/../../config/domains/${var.environment}.yaml"))
}

# Credencial do UC baseada na managed identity do Access Connector (sem segredos).
resource "databricks_storage_credential" "lake" {
  name    = "edp_${var.environment}_lake"
  comment = "Access Connector da plataforma (managed identity). Gerenciado por platform-infra."
  # Alinha com o state (gravado por um apply parcial). Alterar este atributo exige um update
  # que a API recusa enquanto houver external locations dependentes.
  force_destroy = true

  azure_managed_identity {
    access_connector_id = local.foundation.databricks_access_connector_id
  }
}

# Raiz do managed storage dos catálogos de domínio (<dominio>_<env>).
resource "databricks_external_location" "lakehouse" {
  name            = "edp_${var.environment}_lakehouse"
  url             = local.lakehouse_url
  credential_name = databricks_storage_credential.lake.name
  comment         = "Managed storage dos catálogos de domínio. Gerenciado por platform-infra."
}

# Identidade usada pelos pipelines de domínio (bundle deploy / run_as dos jobs).
# Managed identity entra no Databricks como service principal pelo client ID.
resource "databricks_service_principal" "deployer" {
  application_id        = var.deployer_client_id
  display_name          = "id-gh-edp-deployer"
  workspace_access      = true
  databricks_sql_access = true
}

module "domain_data" {
  source   = "../../modules/domain-data"
  for_each = local.domains

  name                     = each.key
  environment              = var.environment
  storage_account_id       = local.foundation.storage_account_id
  storage_account_name     = local.foundation.storage_account_name
  lakehouse_container_name = local.foundation.lakehouse_container_name
  storage_credential_name  = databricks_storage_credential.lake.name
  deployer_application_id  = databricks_service_principal.deployer.application_id
  catalog_grants           = try(each.value.catalog_grants, {})

  depends_on = [databricks_external_location.lakehouse]
}
