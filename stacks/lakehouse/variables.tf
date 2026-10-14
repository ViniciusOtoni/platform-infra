variable "subscription_id" {
  description = "Subscription Azure da plataforma."
  type        = string
}

variable "environment" {
  description = "Nome do ambiente (dev, prd)."
  type        = string
}

variable "tfstate_resource_group_name" {
  description = "Resource group do storage de tfstate (criado no bootstrap)."
  type        = string
  default     = "rg-edp-tfstate"
}

variable "tfstate_storage_account_name" {
  description = "Storage account do tfstate (criado no bootstrap)."
  type        = string
  default     = "sttfedpviniciusotoni"
}

variable "deployer_client_id" {
  description = "Client ID da identidade deployer (output deployer_client_id do bootstrap)."
  type        = string
}

variable "workspace_admins" {
  description = "Usuários humanos (UPN) administradores do workspace: acesso declarado como código."
  type        = list(string)
  default     = []
}
