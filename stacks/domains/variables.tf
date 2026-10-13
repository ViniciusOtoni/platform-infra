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

variable "gitops_repository_url" {
  description = "Repositório GitOps reconciliado pelo Flux."
  type        = string
  default     = "https://github.com/ViniciusOtoni/platform-gitops"
}

variable "gitops_branch" {
  description = "Branch reconciliada pelo Flux."
  type        = string
  default     = "main"
}

variable "domains" {
  description = <<-EOT
    Domínios on-boarded neste ambiente (onboarding = PR adicionando uma entrada).
    Ver modules/domain/variables.tf para o significado de cada campo.
  EOT
  type = map(object({
    aggregates = list(object({
      name                   = string
      major_version          = optional(number, 1)
      partition_count        = optional(number, 2)
      message_retention_days = optional(number, 1)
      consumer_groups        = optional(list(string), [])
    }))
    workloads                = optional(list(string), [])
    catalog_grants           = optional(map(list(string)), {})
    capture_interval_seconds = optional(number, 300)
  }))
  default = {}
}
