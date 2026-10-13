output "tenant_id" {
  value = data.azurerm_client_config.current.tenant_id
}

output "subscription_id" {
  value = var.subscription_id
}

output "infra_client_id" {
  description = "AZURE_CLIENT_ID do repositório platform-infra."
  value       = module.github_identity["infra"].client_id
}

output "deployer_client_id" {
  description = "AZURE_CLIENT_ID dos repositórios de domínio."
  value       = module.github_identity["deployer"].client_id
}

output "deployer_object_id" {
  description = "Object ID do SP deployer (usado em envs/<env>.tfvars dos stacks)."
  value       = module.github_identity["deployer"].object_id
}

output "tfstate_storage_account_name" {
  value = azurerm_storage_account.tfstate.name
}
