# Foundation (C1, ADR-0010): camada PERSISTENTE e barata da plataforma.
# ADLS (dados do Lakehouse e arquivos do Capture), ACR (imagens) e Databricks (workspace + Access Connector).
# O runtime caro (Event Hubs, AKS, Postgres) fica no stack "runtime", que é efêmero.

locals {
  prefix = "edp-${var.environment}"
  tags = {
    project    = "edp"
    env        = var.environment
    managed_by = "terraform"
    stack      = "foundation"
  }
}

# Sufixo estável: também é usado pelo runtime para manter nomes globais iguais entre sessões.
resource "random_string" "suffix" {
  length  = 5
  special = false
  upper   = false
}

resource "azurerm_resource_group" "this" {
  name     = "rg-${local.prefix}"
  location = var.location
  tags     = local.tags
}

# ---------------------------------------------------------------- ADLS Gen2
# Containers: "lakehouse" (managed storage do UC) e "capture-<dominio>" (stack lakehouse).
resource "azurerm_storage_account" "lake" {
  name                            = "stedp${var.environment}${random_string.suffix.result}"
  resource_group_name             = azurerm_resource_group.this.name
  location                        = azurerm_resource_group.this.location
  account_tier                    = "Standard"
  account_replication_type        = "LRS"
  account_kind                    = "StorageV2"
  is_hns_enabled                  = true
  min_tls_version                 = "TLS1_2"
  allow_nested_items_to_be_public = false
  # Mantido habilitado: o Event Hubs Capture (sem managed identity no azurerm) depende dele.
  shared_access_key_enabled = true
  tags                      = local.tags
}

resource "azurerm_storage_container" "lakehouse" {
  name                  = "lakehouse"
  storage_account_id    = azurerm_storage_account.lake.id
  container_access_type = "private"
}

# ---------------------------------------------------------------- ACR
resource "azurerm_container_registry" "this" {
  name                = "acredp${var.environment}${random_string.suffix.result}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  sku                 = "Basic"
  admin_enabled       = false
  tags                = local.tags
}

resource "azurerm_role_assignment" "deployer_acr_push" {
  scope                = azurerm_container_registry.this.id
  role_definition_name = "AcrPush"
  principal_id         = var.deployer_principal_id
}

# ---------------------------------------------------------------- Databricks
resource "azurerm_databricks_workspace" "this" {
  name                        = "dbw-${local.prefix}"
  resource_group_name         = azurerm_resource_group.this.name
  location                    = azurerm_resource_group.this.location
  sku                         = "premium" # Unity Catalog exige premium
  managed_resource_group_name = "rg-${local.prefix}-dbw-managed"
  tags                        = local.tags
}

resource "azurerm_databricks_access_connector" "this" {
  name                = "dbac-${local.prefix}"
  resource_group_name = azurerm_resource_group.this.name
  location            = azurerm_resource_group.this.location
  tags                = local.tags

  identity {
    type = "SystemAssigned"
  }
}

# Storage credential do UC: lê/escreve "lakehouse" e lê "capture-*".
resource "azurerm_role_assignment" "access_connector_storage" {
  scope                = azurerm_storage_account.lake.id
  role_definition_name = "Storage Blob Data Contributor"
  principal_id         = azurerm_databricks_access_connector.this.identity[0].principal_id
}

# File events gerenciados pelo UC (Auto Loader / file arrival) criam fila e Event Grid no storage.
resource "azurerm_role_assignment" "access_connector_queue" {
  scope                = azurerm_storage_account.lake.id
  role_definition_name = "Storage Queue Data Contributor"
  principal_id         = azurerm_databricks_access_connector.this.identity[0].principal_id
}

# Managed file events (padrão das external locations novas do UC) criam a assinatura do Event Grid
# no storage: a API exige Microsoft.Storage/storageAccounts/write no escopo do storage (linked scope).
# Sem esta role, o file arrival trigger falha com LinkedAuthorizationFailed e nunca dispara.
resource "azurerm_role_assignment" "access_connector_storage_account" {
  scope                = azurerm_storage_account.lake.id
  role_definition_name = "Storage Account Contributor"
  principal_id         = azurerm_databricks_access_connector.this.identity[0].principal_id
}

resource "azurerm_role_assignment" "access_connector_eventgrid" {
  scope                = azurerm_resource_group.this.id
  role_definition_name = "EventGrid EventSubscription Contributor"
  principal_id         = azurerm_databricks_access_connector.this.identity[0].principal_id
}

# O Unity Catalog valida o acesso da credencial ao criar external locations (stack lakehouse).
# Numa foundation recém-criada, as roles do Access Connector ainda não propagaram e a validação
# falha com 403. Espera a propagação antes de expor o Access Connector aos stacks seguintes.
resource "time_sleep" "access_connector_rbac" {
  create_duration = "120s"

  triggers = {
    storage  = azurerm_role_assignment.access_connector_storage.id
    queue    = azurerm_role_assignment.access_connector_queue.id
    eventgrd = azurerm_role_assignment.access_connector_eventgrid.id
    account  = azurerm_role_assignment.access_connector_storage_account.id
  }
}
