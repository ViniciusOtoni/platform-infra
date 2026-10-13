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

variable "tenant_id" {
  description = "Tenant do Entra ID (administradores do Postgres)."
  type        = string
}

variable "resource_group_name" {
  description = "Resource group da plataforma."
  type        = string
}

variable "location" {
  description = "Região Azure."
  type        = string
}

variable "eventhub_namespace_id" {
  description = "ID do namespace Event Hubs."
  type        = string
}

variable "eventhub_namespace_name" {
  description = "Nome do namespace Event Hubs."
  type        = string
}

variable "storage_account_id" {
  description = "ID do ADLS Gen2 (destino do Capture)."
  type        = string
}

variable "capture_container_name" {
  description = "Container persistente de capture do domínio (stack lakehouse)."
  type        = string
}

variable "aks_oidc_issuer_url" {
  description = "OIDC issuer do AKS (Workload Identity)."
  type        = string
}

variable "postgres_server_id" {
  description = "ID do Postgres Flexible Server compartilhado."
  type        = string
}

variable "postgres_server_name" {
  description = "Nome do Postgres Flexible Server compartilhado."
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

variable "database" {
  description = "Cria o database <dominio> no Postgres compartilhado."
  type        = bool
  default     = false
}

variable "capture_interval_seconds" {
  description = "Janela de tempo do Event Hubs Capture (60-900). Define parte do freshness."
  type        = number
  default     = 300
}

variable "tags" {
  description = "Tags (já com domain=<nome>)."
  type        = map(string)
  default     = {}
}
