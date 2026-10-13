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
  description = "Client ID (application id) do SP deployer; vira service principal no workspace."
  type        = string
}
