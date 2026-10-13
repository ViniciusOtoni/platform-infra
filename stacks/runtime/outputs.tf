output "eventhub_namespace_fqdn" {
  value = "${azurerm_eventhub_namespace.this.name}.servicebus.windows.net"
}

output "aks_name" {
  value = azurerm_kubernetes_cluster.this.name
}

output "postgres_fqdn" {
  value = azurerm_postgresql_flexible_server.this.fqdn
}

output "domains" {
  description = "Por domínio: event hubs, schema group, database e client IDs das workloads."
  value = {
    for name, m in module.domain_runtime : name => {
      eventhubs           = m.eventhub_names
      schema_group        = m.schema_group_name
      database            = m.database_name
      workload_client_ids = m.workload_client_ids
    }
  }
}

output "flux_substitute_keys" {
  description = "Variáveis disponíveis para os manifests do platform-gitops."
  value       = sort(keys(local.flux_substitute))
}
