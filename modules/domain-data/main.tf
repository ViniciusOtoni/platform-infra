# Parte PERSISTENTE do onboarding de domínio (ADR-0004 / ADR-0010):
# container de capture no ADLS, external location (read-only) e catálogo UC com bronze/silver/gold.
# Sobrevive ao ciclo up/down do runtime: os eventos já capturados e as tabelas permanecem.

terraform {
  required_version = ">= 1.9"
  required_providers {
    azurerm = {
      source  = "hashicorp/azurerm"
      version = ">= 4.40, < 5.0"
    }
    databricks = {
      source  = "databricks/databricks"
      version = ">= 1.90, < 2.0"
    }
  }
}

locals {
  catalog_name = "${var.name}_${var.environment}"
}

resource "azurerm_storage_container" "capture" {
  name                  = "capture-${var.name}"
  storage_account_id    = var.storage_account_id
  container_access_type = "private"
}

resource "databricks_external_location" "capture" {
  name            = "${var.name}_${var.environment}_capture"
  url             = "abfss://${azurerm_storage_container.capture.name}@${var.storage_account_name}.dfs.core.windows.net/"
  credential_name = var.storage_credential_name
  read_only       = true
  # Managed file events (Event Grid no storage) alimentam o file arrival trigger e o Auto Loader.
  # Exigem Storage Account Contributor no Access Connector (stack foundation, ADR-0001).
  enable_file_events = true
  comment            = "Arquivos do Event Hubs Capture do domínio ${var.name} (fonte da Bronze)."
}

resource "databricks_catalog" "this" {
  name         = local.catalog_name
  storage_root = "abfss://${var.lakehouse_container_name}@${var.storage_account_name}.dfs.core.windows.net/${local.catalog_name}"
  comment      = "Catálogo do bounded context ${var.name} (${var.environment})."
  # Ambiente de estudo: permite destruir o catálogo com tabelas (workflow teardown).
  force_destroy = true
  properties = {
    domain = var.name
    env    = var.environment
  }
}

resource "databricks_schema" "layer" {
  for_each = toset(["bronze", "silver", "gold"])

  catalog_name  = databricks_catalog.this.name
  name          = each.key
  force_destroy = true
  comment       = "Camada ${each.key} do domínio ${var.name}."
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
