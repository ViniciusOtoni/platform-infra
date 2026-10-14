output "suffix" {
  description = "Sufixo estável para nomes globais (reutilizado pelo runtime)."
  value       = random_string.suffix.result
}

output "resource_group_name" {
  value = azurerm_resource_group.this.name
}

output "resource_group_id" {
  value = azurerm_resource_group.this.id
}

output "location" {
  value = azurerm_resource_group.this.location
}

output "storage_account_id" {
  value = azurerm_storage_account.lake.id
}

output "storage_account_name" {
  value = azurerm_storage_account.lake.name
}

output "lakehouse_container_name" {
  value = azurerm_storage_container.lakehouse.name
}

output "acr_id" {
  value = azurerm_container_registry.this.id
}

output "acr_name" {
  value = azurerm_container_registry.this.name
}

output "acr_login_server" {
  value = azurerm_container_registry.this.login_server
}

output "databricks_workspace_resource_id" {
  value = azurerm_databricks_workspace.this.id
}

output "databricks_workspace_url" {
  value = "https://${azurerm_databricks_workspace.this.workspace_url}"
}

output "databricks_access_connector_id" {
  # Só é exposto após a propagação das roles (time_sleep).
  value      = azurerm_databricks_access_connector.this.id
  depends_on = [time_sleep.access_connector_rbac]
}
