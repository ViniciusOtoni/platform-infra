# Parte EFÊMERA do onboarding de domínio (ADR-0004 / ADR-0010), recriada a cada `env-up`:
# event hubs por agregado (+ Capture para o container persistente), consumer groups, schema group,
# identidades das workloads (Workload Identity), RBAC e database no Postgres compartilhado.

locals {
  aggregates = { for a in var.aggregates : a.name => a }

  consumer_groups = merge([
    for a in var.aggregates : {
      for cg in a.consumer_groups : "${a.name}/${cg}" => { aggregate = a.name, name = cg }
    }
  ]...)
}

# ---------------------------------------------------------------- Event backbone
resource "azurerm_eventhub" "aggregate" {
  for_each = local.aggregates

  name              = "${var.name}.${each.key}.v${each.value.major_version}"
  namespace_id      = var.eventhub_namespace_id
  partition_count   = each.value.partition_count
  message_retention = each.value.message_retention_days

  # Capture -> ADLS (ADR-0001). O container é persistente (stack lakehouse).
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
      blob_container_name = var.capture_container_name
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
  tags                = var.tags
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

# Registrar os schemas da própria Published Language (o produtor registra ao subir, ADR-0003/0010).
resource "azurerm_role_assignment" "schema_registry_contributor" {
  for_each = toset(var.workloads)

  scope                = azurerm_eventhub_namespace_schema_group.this.id
  role_definition_name = "Schema Registry Contributor"
  principal_id         = azurerm_user_assigned_identity.workload[each.key].principal_id
}

# Ler os schemas de qualquer domínio (consumidores da Published Language).
resource "azurerm_role_assignment" "schema_registry_reader" {
  for_each = toset(var.workloads)

  scope                = var.eventhub_namespace_id
  role_definition_name = "Schema Registry Reader"
  principal_id         = azurerm_user_assigned_identity.workload[each.key].principal_id
}

# ---------------------------------------------------------------- Postgres (database-per-service, ADR-0011)
resource "azurerm_postgresql_flexible_server_database" "this" {
  count = var.database ? 1 : 0

  name      = var.name
  server_id = var.postgres_server_id
  charset   = "UTF8"
  collation = "en_US.utf8"
}

# Autenticação só por Entra ID: cada workload do domínio é administrador Entra do servidor.
# Simplificação de estudo (evita bootstrap SQL de roles); ver ADR-0011 para a evolução.
resource "azurerm_postgresql_flexible_server_active_directory_administrator" "workload" {
  for_each = var.database ? toset(var.workloads) : toset([])

  server_name         = var.postgres_server_name
  resource_group_name = var.resource_group_name
  tenant_id           = var.tenant_id
  object_id           = azurerm_user_assigned_identity.workload[each.key].principal_id
  principal_name      = azurerm_user_assigned_identity.workload[each.key].name
  principal_type      = "ServicePrincipal"
}
