output "storage_credential_name" {
  value = databricks_storage_credential.lake.name
}

output "lakehouse_external_location_url" {
  value = databricks_external_location.lakehouse.url
}

output "deployer_application_id" {
  value = databricks_service_principal.deployer.application_id
}
