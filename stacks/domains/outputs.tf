output "domains" {
  description = "Resumo por domínio: event hubs, capture, catálogo e client IDs das workloads."
  value = {
    for name, m in module.domain : name => {
      eventhubs           = m.eventhub_names
      capture_url         = m.capture_url
      catalog             = m.catalog_name
      schema_group        = m.schema_group_name
      workload_client_ids = m.workload_client_ids
    }
  }
}

output "flux_substitute_keys" {
  description = "Variáveis disponíveis para os manifests do platform-gitops."
  value       = sort(keys(local.flux_substitute))
}
