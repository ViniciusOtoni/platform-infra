output "eventhub_names" {
  description = "agregado -> nome do event hub."
  value       = { for k, eh in azurerm_eventhub.aggregate : k => eh.name }
}

output "capture_url" {
  description = "Raiz abfss dos arquivos do Capture (url do file arrival trigger)."
  value       = databricks_external_location.capture.url
}

output "catalog_name" {
  value = databricks_catalog.this.name
}

output "schema_group_name" {
  value = azurerm_eventhub_namespace_schema_group.this.name
}

output "workload_client_ids" {
  description = "workload (ServiceAccount) -> client id da managed identity."
  value       = { for k, id in azurerm_user_assigned_identity.workload : k => id.client_id }
}
