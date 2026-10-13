output "storage_credential_name" {
  value = databricks_storage_credential.lake.name
}

output "lakehouse_external_location_url" {
  value = databricks_external_location.lakehouse.url
}

output "deployer_application_id" {
  value = databricks_service_principal.deployer.application_id
}

output "domains" {
  description = "Por domínio: container de capture, url do capture (file arrival) e catálogo."
  value = {
    for name, m in module.domain_data : name => {
      capture_container = m.capture_container_name
      capture_url       = m.capture_url
      catalog           = m.catalog_name
    }
  }
}
