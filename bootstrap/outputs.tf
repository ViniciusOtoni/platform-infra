output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  value = var.subscription_id
}

output "infra_client_id" {
  description = "AZURE_CLIENT_ID do repositório platform-infra."
  value       = azurerm_user_assigned_identity.github["infra"].client_id
}

output "deployer_client_id" {
  description = "AZURE_CLIENT_ID dos repositórios de domínio (também é o application_id no Databricks)."
  value       = azurerm_user_assigned_identity.github["deployer"].client_id
}

output "deployer_object_id" {
  description = "Principal ID do deployer (usado em envs/<env>.tfvars dos stacks)."
  value       = azurerm_user_assigned_identity.github["deployer"].principal_id
}

output "tfstate_storage_account_name" {
  value = azurerm_storage_account.tfstate.name
}
