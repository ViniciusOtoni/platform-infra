# Landing zone da plataforma (C1): recursos compartilhados por todos os domínios.

locals {
  prefix = "edp-${var.environment}"
  tags = {
    project    = "edp"
    env        = var.environment
    managed_by = "terraform"
    stack      = "core"
  }
}

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
# Um storage para o Lakehouse: container "lakehouse" (managed storage do UC)
# e containers "capture-<dominio>" (criados no módulo domain).
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

# ---------------------------------------------------------------- Event Hubs (backbone)
resource "azurerm_eventhub_namespace" "this" {
  name                          = "evhns-${local.prefix}-${random_string.suffix.result}"
  resource_group_name           = azurerm_resource_group.this.name
  location                      = azurerm_resource_group.this.location
  sku                           = "Standard"
  capacity                      = var.eventhub_capacity
  local_authentication_enabled  = false # sem SAS: apenas Entra ID (Workload Identity)
  public_network_access_enabled = true
  minimum_tls_version           = "1.2"
  tags                          = local.tags
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

# ---------------------------------------------------------------- AKS + Flux
resource "azurerm_kubernetes_cluster" "this" {
  name                      = "aks-${local.prefix}"
  resource_group_name       = azurerm_resource_group.this.name
  location                  = azurerm_resource_group.this.location
  dns_prefix                = "aks-${local.prefix}"
  sku_tier                  = "Free"
  oidc_issuer_enabled       = true
  workload_identity_enabled = true
  tags                      = local.tags

  default_node_pool {
    name                        = "system"
    vm_size                     = var.aks_node_vm_size
    node_count                  = var.aks_node_count
    os_disk_type                = "Managed"
    temporary_name_for_rotation = "systemtmp"
  }

  identity {
    type = "SystemAssigned"
  }

  network_profile {
    network_plugin      = "azure"
    network_plugin_mode = "overlay"
  }
}

resource "azurerm_role_assignment" "aks_acr_pull" {
  scope                            = azurerm_container_registry.this.id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}

# Flux v2 gerenciado pela Azure (ADR-0007). A configuração (repo/kustomizations)
# fica no stack "domains", que conhece as identidades das workloads.
resource "azurerm_kubernetes_cluster_extension" "flux" {
  name           = "flux"
  cluster_id     = azurerm_kubernetes_cluster.this.id
  extension_type = "microsoft.flux"
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

resource "azurerm_role_assignment" "access_connector_eventgrid" {
  scope                = azurerm_resource_group.this.id
  role_definition_name = "EventGrid EventSubscription Contributor"
  principal_id         = azurerm_databricks_access_connector.this.identity[0].principal_id
}
