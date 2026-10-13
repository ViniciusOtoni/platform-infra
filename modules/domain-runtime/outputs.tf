output "eventhub_names" {
  description = "agregado -> nome do event hub."
  value       = { for k, eh in azurerm_eventhub.aggregate : k => eh.name }
}

output "schema_group_name" {
  value = azurerm_eventhub_namespace_schema_group.this.name
}

output "workload_client_ids" {
  description = "workload (ServiceAccount) -> client id da managed identity."
  value       = { for k, id in azurerm_user_assigned_identity.workload : k => id.client_id }
}

output "workload_identity_names" {
  description = "workload -> nome da managed identity (usuário Entra no Postgres)."
  value       = { for k, id in azurerm_user_assigned_identity.workload : k => id.name }
}

output "database_name" {
  value = var.database ? azurerm_postgresql_flexible_server_database.this[0].name : null
}
