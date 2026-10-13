# Domínios on-boarded (C2) + configuração GitOps do cluster (Flux).

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

data "terraform_remote_state" "lakehouse" {
  backend = "azurerm"
  config = {
    resource_group_name  = var.tfstate_resource_group_name
    storage_account_name = var.tfstate_storage_account_name
    container_name       = "tfstate"
    key                  = "lakehouse/${var.environment}.tfstate"
    use_azuread_auth     = true
  }
}

data "azurerm_client_config" "current" {}

locals {
  core      = data.terraform_remote_state.core.outputs
  lakehouse = data.terraform_remote_state.lakehouse.outputs

  tags = {
    project    = "edp"
    env        = var.environment
    managed_by = "terraform"
    stack      = "domains"
  }
}

module "domain" {
  source   = "../../modules/domain"
  for_each = var.domains

  name        = each.key
  environment = var.environment

  resource_group_name      = local.core.resource_group_name
  location                 = local.core.location
  eventhub_namespace_id    = local.core.eventhub_namespace_id
  eventhub_namespace_name  = local.core.eventhub_namespace_name
  storage_account_id       = local.core.storage_account_id
  storage_account_name     = local.core.storage_account_name
  lakehouse_container_name = local.core.lakehouse_container_name
  aks_oidc_issuer_url      = local.core.aks_oidc_issuer_url
  storage_credential_name  = local.lakehouse.storage_credential_name
  deployer_application_id  = local.lakehouse.deployer_application_id

  aggregates               = each.value.aggregates
  workloads                = each.value.workloads
  catalog_grants           = each.value.catalog_grants
  capture_interval_seconds = each.value.capture_interval_seconds
  tags                     = local.tags
}

# ---------------------------------------------------------------- GitOps (Flux)
locals {
  # Variáveis ${...} disponíveis nos manifests do platform-gitops (postBuild.substitute).
  # Ex.: PEDIDOS_PEDIDOS_API_CLIENT_ID
  workload_client_id_vars = merge([
    for domain, m in module.domain : {
      for workload, client_id in m.workload_client_ids :
      upper(replace("${domain}_${workload}_CLIENT_ID", "-", "_")) => client_id
    }
  ]...)

  flux_substitute = merge(
    {
      AZURE_TENANT_ID         = data.azurerm_client_config.current.tenant_id
      EVENTHUB_NAMESPACE_FQDN = local.core.eventhub_namespace_fqdn
      ACR_LOGIN_SERVER        = local.core.acr_login_server
      ENVIRONMENT             = var.environment
    },
    local.workload_client_id_vars,
  )
}

resource "azurerm_kubernetes_flux_configuration" "platform" {
  name       = "platform-gitops"
  cluster_id = local.core.aks_id
  namespace  = "flux-system"
  scope      = "cluster"

  git_repository {
    url                      = var.gitops_repository_url
    reference_type           = "branch"
    reference_value          = var.gitops_branch
    sync_interval_in_seconds = 60
  }

  kustomizations {
    name                       = "infrastructure"
    path                       = "./clusters/${var.environment}/infrastructure"
    sync_interval_in_seconds   = 120
    garbage_collection_enabled = true
  }

  kustomizations {
    name                       = "domains"
    path                       = "./clusters/${var.environment}/domains"
    depends_on                 = ["infrastructure"]
    sync_interval_in_seconds   = 120
    garbage_collection_enabled = true

    post_build {
      substitute = local.flux_substitute
    }
  }
}
