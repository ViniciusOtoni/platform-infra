output "resource_group_name" {
  value = azurerm_resource_group.this.name
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

output "eventhub_namespace_id" {
  value = azurerm_eventhub_namespace.this.id
}

output "eventhub_namespace_name" {
  value = azurerm_eventhub_namespace.this.name
}

output "eventhub_namespace_fqdn" {
  value = "${azurerm_eventhub_namespace.this.name}.servicebus.windows.net"
}

output "acr_name" {
  value = azurerm_container_registry.this.name
}

output "acr_login_server" {
  value = azurerm_container_registry.this.login_server
}

output "aks_id" {
  value = azurerm_kubernetes_cluster.this.id
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "aks_oidc_issuer_url" {
  value = azurerm_kubernetes_cluster.this.oidc_issuer_url
}

output "databricks_workspace_resource_id" {
  value = azurerm_databricks_workspace.this.id
}

output "databricks_workspace_url" {
  value = "https://${azurerm_databricks_workspace.this.workspace_url}"
}

output "databricks_access_connector_id" {
  value = azurerm_databricks_access_connector.this.id
}
