output "capture_container_name" {
  value = azurerm_storage_container.capture.name
}

output "capture_url" {
  description = "Raiz abfss dos arquivos do Capture (url do file arrival trigger)."
  value       = databricks_external_location.capture.url
}

output "catalog_name" {
  value = databricks_catalog.this.name
}
