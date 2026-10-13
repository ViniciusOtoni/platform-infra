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
  }
}

provider "azurerm" {
  features {}
  subscription_id     = var.subscription_id
  storage_use_azuread = true
}


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
# User-Assigned Managed Identities com federated credentials do GitHub (ADR-0009).
# Usamos UAMI (recurso ARM) e não App Registration: o tenant não permite que o usuário
# seja owner das apps que cria, o que bloqueia SP e federated credentials no Entra ID.
# infra:    platform-infra (Terraform). Contributor + RBAC Administrator na subscription.
# deployer: repos de domínio (*-service, *-data). Permissões dadas pelos stacks.
resource "azurerm_user_assigned_identity" "github" {
  for_each = var.github_identities

  name                = "id-gh-edp-${each.key}"
  resource_group_name = azurerm_resource_group.tfstate.name
  location            = azurerm_resource_group.tfstate.location
  tags                = local.tags
}

locals {
  federated_credentials = merge([
    for role, subjects in var.github_identities : {
      for s in subjects : "${role}/${s}" => { role = role, subject = s }
    }
  ]...)
}

# Atenção: a Azure não aceita escrita concorrente de federated credentials na mesma
# identidade. Aplique este stack com `-parallelism=1`.
resource "azurerm_federated_identity_credential" "github" {
  for_each = local.federated_credentials

  name                = substr(replace(each.value.subject, "/[^a-zA-Z0-9-_]/", "-"), 0, 120)
  resource_group_name = azurerm_resource_group.tfstate.name
  parent_id           = azurerm_user_assigned_identity.github[each.value.role].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = "https://token.actions.githubusercontent.com"
  subject             = "repo:${var.github_owner}/${each.value.subject}"
}

resource "azurerm_role_assignment" "infra_contributor" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Contributor"
  principal_id         = azurerm_user_assigned_identity.github["infra"].principal_id
}

resource "azurerm_role_assignment" "infra_rbac_admin" {
  scope                = data.azurerm_subscription.current.id
  role_definition_name = "Role Based Access Control Administrator"
  principal_id         = azurerm_user_assigned_identity.github["infra"].principal_id
}

resource "azurerm_role_assignment" "infra_tfstate" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_user_assigned_identity.github["infra"].principal_id
}

# O deployer lê outputs dos stacks (terraform_remote_state) em pipelines de domínio.
resource "azurerm_role_assignment" "deployer_tfstate_reader" {
  scope                = azurerm_storage_account.tfstate.id
  role_definition_name = "Storage Blob Data Reader"
  principal_id         = azurerm_user_assigned_identity.github["deployer"].principal_id
}
