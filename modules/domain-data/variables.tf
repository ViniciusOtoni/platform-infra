variable "name" {
  description = "Nome do bounded context (minúsculo). Ex.: pedidos."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9]{2,20}$", var.name))
    error_message = "name deve ter 3-21 caracteres [a-z0-9], começando com letra."
  }
}

variable "environment" {
  description = "Nome do ambiente (dev, prd)."
  type        = string
}

variable "storage_account_id" {
  description = "ID do ADLS Gen2 da plataforma."
  type        = string
}

variable "storage_account_name" {
  description = "Nome do ADLS Gen2 da plataforma."
  type        = string
}

variable "lakehouse_container_name" {
  description = "Container do managed storage dos catálogos."
  type        = string
}

variable "storage_credential_name" {
  description = "Storage credential do UC."
  type        = string
}

variable "deployer_application_id" {
  description = "Application (client) ID da identidade deployer; recebe ALL_PRIVILEGES no catálogo."
  type        = string
}

variable "catalog_grants" {
  description = "Grants extras no catálogo: principal -> privilégios."
  type        = map(list(string))
  default     = {}
}

variable "subscription_id" {
  description = "Subscription onde a Databricks cria a fila dos managed file events."
  type        = string
}

variable "file_events_resource_group" {
  description = "Resource group (o do storage) onde a Databricks cria a fila dos managed file events."
  type        = string
}
