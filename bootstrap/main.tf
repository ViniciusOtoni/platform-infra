# Bootstrap (executado UMA vez, localmente, com `az login` de um usuário Owner da subscription).
# Cria o que os pipelines precisam para existir: storage do tfstate e as identidades OIDC do GitHub.
# State local (gitignored): este stack é o "ovo" da galinha.

terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = "~> 4.40"
    }
    azuread = {
      source  = "hashicorp/azuread"
      version = "~> 3.4"
    }
  }
}

provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}

provider "azuread" {}

data "azurerm_client_config" "current" {}
data "azurerm_subscription" "current" {}

locals {
  tags = {
    project    = "edp"
    managed_by = "terraform"
    stack      = "bootstrap"
  }
}

# ---------------------------------------------------------------- tfstate
resource "azurerm_resource_group" "tfstate" {
  name     = "rg-edp-tfstate"
  location = var.location
  tags     = local.tags
}

resource "azurerm_storage_account" "tfstate" {
  name                            = var.tfstate_storage_account_name
  resource_group_name             = azurerm_resource_group.tfstate.name
  location                        = azurerm_resource_group.tfstate.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  min_tls_version                 = "TLS1_2"
  shared_access_key_enabled       = false
  allow_nested_items_to_be_public = false
  default_to_oauth_authentication = true
  tags                            = local.tags

  blob_properties {
    versioning_enabled = true
    delete_retention_policy {
      days = 7
    }
  }
}

resource "azurerm_storage_container" "tfstate" {
  name                  = "tfstate"
  storage_account_id    = azurerm_storage_account.tfstate.id
  container_access_type = "private"
}

# Quem roda o bootstrap também precisa ler/escrever o state via Entra ID.
resource "azurerm_role_assignment" "tfstate_operator" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = data.azurerm_client_config.current.object_id
}

# ---------------------------------------------------------------- identidades GitHub (OIDC)
# infra:    platform-infra (Terraform). Contributor + RBAC Administrator na subscription.
# deployer: repos de domínio (*-service, *-data). Permissões dadas pelos stacks core/lakehouse/domains.
module "github_identity" {
  source   = "./github-identity"
  for_each = var.github_identities

  display_name = "gh-edp-${each.key}"
  github_owner = var.github_owner
  subjects     = each.value
}

resource "azurerm_role_assignment" "infra_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = module.github_identity["infra"].object_id
}

resource "azurerm_role_assignment" "infra_rbac_admin" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = module.github_identity["infra"].object_id
}

resource "azurerm_role_assignment" "infra_tfstate" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = module.github_identity["infra"].object_id
}

# O deployer lê outputs dos stacks (terraform_remote_state) em pipelines de domínio.
resource "azurerm_role_assignment" "deployer_tfstate_reader" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = module.github_identity["deployer"].object_id
}
