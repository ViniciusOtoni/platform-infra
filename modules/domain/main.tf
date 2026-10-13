# Módulo de onboarding de domínio (C2 / ADR-0004): Bounded Context = unidade de provisionamento.
# Cria, para um domínio: event hubs por agregado (+ Capture), consumer groups, schema group,
# container de capture, identidades de workload (Workload Identity) e catálogo UC com bronze/silver/gold.

locals {
  tags         = merge(var.tags, { domain = var.name })
  catalog_name = "${var.name}_${var.environment}"
  aggregates   = { for a in var.aggregates : a.name => a }

  consumer_groups = merge([
    for a in var.aggregates : {
      for cg in a.consumer_groups : "${a.name}/${cg}" => { aggregate = a.name, name = cg }
    }
  ]...)
}

# ---------------------------------------------------------------- Event backbone
resource "azurerm_storage_container" "capture" {
  name                  = "capture-${var.name}"
  storage_account_id    = var.storage_account_id
  container_access_type = "private"
}

resource "azurerm_eventhub" "aggregate" {
  for_each = local.aggregates

  name              = "${var.name}.${each.key}.v${each.value.major_version}"
  namespace_id      = var.eventhub_namespace_id
  partition_count   = each.value.partition_count
  message_retention = each.value.message_retention_days

  # Capture -> ADLS (ADR-0001).
  # Caminho: capture-<dominio>/<namespace>/<eventhub>/<particao>/AAAA/MM/DD/HH/mm/ss.avro
  capture_description {
    enabled             = true
    encoding            = "Avro"
    interval_in_seconds = var.capture_interval_seconds
    size_limit_in_bytes = 314572800
    skip_empty_archives = true

    destination {
      name                = "EventHubArchive.AzureBlockBlob"
      archive_name_format = "{Namespace}/{EventHub}/{PartitionId}/{Year}/{Month}/{Day}/{Hour}/{Minute}/{Second}"
      blob_container_name = azurerm_storage_container.capture.name
      storage_account_id  = var.storage_account_id
    }
  }
}

resource "azurerm_eventhub_consumer_group" "this" {
  for_each = local.consumer_groups

  name                = each.value.name
  namespace_name      = var.eventhub_namespace_name
  eventhub_name       = azurerm_eventhub.aggregate[each.value.aggregate].name
  resource_group_name = var.resource_group_name
}

# Schema group do domínio (ADR-0003). Compatibilidade é checada no CI (contracts-tooling), não no registry.
resource "azurerm_eventhub_namespace_schema_group" "this" {
  name                 = var.name
  namespace_id         = var.eventhub_namespace_id
  schema_compatibility = "None"
  schema_type          = "Json"
}

# ---------------------------------------------------------------- Workload Identity
resource "azurerm_user_assigned_identity" "workload" {
  for_each = toset(var.workloads)

  name                = "id-${var.name}-${each.key}-${var.environment}"
  resource_group_name = var.resource_group_name
  location            = var.location
  tags                = local.tags
}

resource "azurerm_federated_identity_credential" "workload" {
  for_each = toset(var.workloads)

  name                = "aks-${var.name}-${each.key}"
  resource_group_name = var.resource_group_name
  parent_id           = azurerm_user_assigned_identity.workload[each.key].id
  audience            = ["api://AzureADTokenExchange"]
  issuer              = var.aks_oidc_issuer_url
  # Namespace do domínio = nome do domínio (ver platform-gitops/domains/<dominio>).
  subject = "system:serviceaccount:${var.name}:${each.key}"
}

# Publicar nos event hubs do próprio domínio.
resource "azurerm_role_assignment" "sender" {
  for_each = {
    for pair in setproduct(var.workloads, keys(local.aggregates)) : "${pair[0]}/${pair[1]}" => pair
  }

  scope                = azurerm_eventhub.aggregate[each.value[1]].id
  role_definition_name = "Azure Event Hubs Data Sender"
  principal_id         = azurerm_user_assigned_identity.workload[each.value[0]].principal_id
}

# Consumir eventos de integração de qualquer domínio (a Published Language é pública na plataforma).
resource "azurerm_role_assignment" "receiver" {
  for_each = toset(var.workloads)

  scope                = var.eventhub_namespace_id
  role_definition_name = "Azure Event Hubs Data Receiver"
  principal_id         = azurerm_user_assigned_identity.workload[each.key].principal_id
}

# ---------------------------------------------------------------- Unity Catalog
resource "databricks_external_location" "capture" {
  name            = "${var.name}_${var.environment}_capture"
  url             = "abfss://${azurerm_storage_container.capture.name}@${var.storage_account_name}.dfs.core.windows.net/"
  credential_name = var.storage_credential_name
  read_only       = true
  comment         = "Arquivos do Event Hubs Capture do domínio ${var.name} (fonte da Bronze)."
}

resource "databricks_catalog" "this" {
  name         = local.catalog_name
  storage_root = "abfss://${var.lakehouse_container_name}@${var.storage_account_name}.dfs.core.windows.net/${local.catalog_name}"
  comment      = "Catálogo do bounded context ${var.name} (${var.environment})."
  properties = {
    domain = var.name
    env    = var.environment
  }
}

resource "databricks_schema" "layer" {
  for_each = toset(["bronze", "silver", "gold"])

  catalog_name = databricks_catalog.this.name
  name         = each.key
  comment      = "Camada ${each.key} do domínio ${var.name}."
}

resource "databricks_grants" "catalog" {
  catalog = databricks_catalog.this.name

  grant {
    principal  = var.deployer_application_id
    privileges = ["ALL_PRIVILEGES"]
  }

  dynamic "grant" {
    for_each = var.catalog_grants
    content {
      principal  = grant.key
      privileges = grant.value
    }
  }
}

resource "databricks_grants" "capture" {
  external_location = databricks_external_location.capture.id

  grant {
    principal  = var.deployer_application_id
    privileges = ["READ_FILES"]
  }
}
