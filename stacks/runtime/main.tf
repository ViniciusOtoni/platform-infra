# Runtime (EFÊMERO, ADR-0010): sobe com o workflow `env` (action=up) e é destruído com action=down
# (e automaticamente toda noite). Contém tudo que cobra por hora:
# Event Hubs (+ Capture), AKS (+ Flux), Postgres Flexible e a parte de runtime dos domínios.

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
  foundation = data.terraform_remote_state.foundation.outputs
  lakehouse  = data.terraform_remote_state.lakehouse.outputs
  domains    = yamldecode(file("${path.module}/../../config/domains/${var.environment}.yaml"))

  prefix = "edp-${var.environment}"
  # Sufixo da foundation: nomes globais estáveis entre sessões (mesmo caminho de Capture).
  suffix = local.foundation.suffix

  tags = {
    project    = "edp"
    env        = var.environment
    managed_by = "terraform"
    stack      = "runtime"
    lifecycle  = "ephemeral"
  }
}

# ---------------------------------------------------------------- Event Hubs (backbone)
resource "azurerm_eventhub_namespace" "this" {
  name                          = "evhns-${local.prefix}-${local.suffix}"
  resource_group_name           = local.foundation.resource_group_name
  location                      = local.foundation.location
  sku                           = "Standard"
  capacity                      = var.eventhub_capacity
  local_authentication_enabled  = false # sem SAS: apenas Entra ID (Workload Identity)
  public_network_access_enabled = true
  minimum_tls_version           = "1.2"
  tags                          = local.tags
}

# ---------------------------------------------------------------- AKS
resource "azurerm_kubernetes_cluster" "this" {
  name                      = "aks-${local.prefix}"
  resource_group_name       = local.foundation.resource_group_name
  location                  = local.foundation.location
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
    os_disk_size_gb             = 30
    temporary_name_for_rotation = "systemtmp"

    # Valores que a Azure aplica por padrão; declarados para não gerar drift no plan.
    upgrade_settings {
      max_surge                     = "10%"
      drain_timeout_in_minutes      = 0
      node_soak_duration_in_minutes = 0
    }
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
  scope                            = local.foundation.acr_id
  role_definition_name             = "AcrPull"
  principal_id                     = azurerm_kubernetes_cluster.this.kubelet_identity[0].object_id
  skip_service_principal_aad_check = true
}

# Flux v2 gerenciado pela Azure (ADR-0007).
resource "azurerm_kubernetes_cluster_extension" "flux" {
  name           = "flux"
  cluster_id     = azurerm_kubernetes_cluster.this.id
  extension_type = "microsoft.flux"
}

# ---------------------------------------------------------------- Postgres Flexible (ADR-0011)
# Servidor compartilhado, um database por domínio. Autenticação somente Entra ID.
resource "azurerm_postgresql_flexible_server" "this" {
  name                          = "psql-${local.prefix}-${local.suffix}"
  resource_group_name           = local.foundation.resource_group_name
  location                      = var.postgres_location
  version                       = "16"
  sku_name                      = var.postgres_sku
  storage_mb                    = 32768
  backup_retention_days         = 7
  public_network_access_enabled = true
  tags                          = local.tags

  # A zona é escolhida pela Azure na criação.
  lifecycle {
    ignore_changes = [zone]
  }

  authentication {
    active_directory_auth_enabled = true
    password_auth_enabled         = false
    tenant_id                     = data.azurerm_client_config.current.tenant_id
  }
}

# AKS sem IP de saída fixo: libera tráfego originado na Azure. A autenticação é só Entra ID.
resource "azurerm_postgresql_flexible_server_firewall_rule" "azure_services" {
  name             = "allow-azure-services"
  server_id        = azurerm_postgresql_flexible_server.this.id
  start_ip_address = "0.0.0.0"
  end_ip_address   = "0.0.0.0"
}

# Administradores humanos (ex.: o usuário que estuda), para inspecionar o banco.
resource "azurerm_postgresql_flexible_server_active_directory_administrator" "human" {
  for_each = var.postgres_human_admins

  server_name         = azurerm_postgresql_flexible_server.this.name
  resource_group_name = local.foundation.resource_group_name
  tenant_id           = data.azurerm_client_config.current.tenant_id
  object_id           = each.value
  principal_name      = each.key
  principal_type      = "User"
}

# ---------------------------------------------------------------- Domínios (parte efêmera)
module "domain_runtime" {
  source   = "../../modules/domain-runtime"
  for_each = local.domains

  name                    = each.key
  environment             = var.environment
  tenant_id               = data.azurerm_client_config.current.tenant_id
  resource_group_name     = local.foundation.resource_group_name
  location                = local.foundation.location
  eventhub_namespace_id   = azurerm_eventhub_namespace.this.id
  eventhub_namespace_name = azurerm_eventhub_namespace.this.name
  storage_account_id      = local.foundation.storage_account_id
  capture_container_name  = local.lakehouse.domains[each.key].capture_container
  aks_oidc_issuer_url     = azurerm_kubernetes_cluster.this.oidc_issuer_url
  postgres_server_id      = azurerm_postgresql_flexible_server.this.id
  postgres_server_name    = azurerm_postgresql_flexible_server.this.name

  aggregates               = each.value.aggregates
  workloads                = try(each.value.workloads, [])
  database                 = try(each.value.database, false)
  capture_interval_seconds = try(each.value.capture_interval_seconds, 300)
  tags                     = merge(local.tags, { domain = each.key })

  # Servidor Postgres aceita uma operação de administrador por vez.
  depends_on = [azurerm_postgresql_flexible_server_active_directory_administrator.human]
}

# ---------------------------------------------------------------- GitOps (Flux)
locals {
  # Variáveis ${...} disponíveis nos manifests do platform-gitops (postBuild.substitute).
  # Ex.: PEDIDOS_PEDIDOS_API_CLIENT_ID, PEDIDOS_PEDIDOS_API_IDENTITY_NAME
  workload_vars = merge(flatten([
    for domain, m in module.domain_runtime : [
      for workload, client_id in m.workload_client_ids : {
        (upper(replace("${domain}_${workload}_CLIENT_ID", "-", "_")))     = client_id
        (upper(replace("${domain}_${workload}_IDENTITY_NAME", "-", "_"))) = m.workload_identity_names[workload]
      }
    ]
  ])...)

  flux_substitute = merge(
    {
      AZURE_TENANT_ID         = data.azurerm_client_config.current.tenant_id
      EVENTHUB_NAMESPACE_FQDN = "${azurerm_eventhub_namespace.this.name}.servicebus.windows.net"
      ACR_LOGIN_SERVER        = local.foundation.acr_login_server
      POSTGRES_HOST           = azurerm_postgresql_flexible_server.this.fqdn
      ENVIRONMENT             = var.environment
    },
    local.workload_vars,
  )
}

resource "azurerm_kubernetes_flux_configuration" "platform" {
  name       = "platform-gitops"
  cluster_id = azurerm_kubernetes_cluster.this.id
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
    # Espera os workloads ficarem saudáveis, mas sem travar novas revisões por 10 min
    # quando um deploy quebra (ex.: imagem inexistente).
    timeout_in_seconds = 180

    post_build {
      substitute = local.flux_substitute
    }
  }

  depends_on = [azurerm_kubernetes_cluster_extension.flux]
}
