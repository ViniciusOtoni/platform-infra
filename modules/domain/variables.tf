variable "name" {
  description = "Nome do bounded context (minúsculo, sem espaços). Ex.: pedidos."
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

variable "resource_group_name" {
  description = "Resource group da plataforma (identidades do domínio são criadas nele)."
  type        = string
}

variable "location" {
  description = "Região Azure."
  type        = string
}

variable "eventhub_namespace_id" {
  description = "ID do namespace Event Hubs da plataforma."
  type        = string
}

variable "eventhub_namespace_name" {
  description = "Nome do namespace Event Hubs da plataforma."
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
  description = "Storage credential do UC (stack lakehouse)."
  type        = string
}

variable "aks_oidc_issuer_url" {
  description = "OIDC issuer do AKS (Workload Identity)."
  type        = string
}

variable "deployer_application_id" {
  description = "Application ID do SP deployer; recebe ALL_PRIVILEGES no catálogo do domínio."
  type        = string
}

variable "aggregates" {
  description = "Agregados do domínio. Cada um vira um event hub <dominio>.<agregado>.v<major> (ADR-0008)."
  type = list(object({
    name                   = string
    major_version          = optional(number, 1)
    partition_count        = optional(number, 2)
    message_retention_days = optional(number, 1)
    consumer_groups        = optional(list(string), [])
  }))
}

variable "workloads" {
  description = "ServiceAccounts do namespace do domínio que recebem Workload Identity (ex.: pedidos-api)."
  type        = list(string)
  default     = []
}

variable "catalog_grants" {
  description = "Grants extras no catálogo: principal -> privilégios (ex.: grupo de analistas)."
  type        = map(list(string))
  default     = {}
}

variable "capture_interval_seconds" {
  description = "Janela de tempo do Event Hubs Capture (60-900). Define parte do freshness."
  type        = number
  default     = 300
}

variable "tags" {
  description = "Tags base da plataforma."
  type        = map(string)
  default     = {}
}
