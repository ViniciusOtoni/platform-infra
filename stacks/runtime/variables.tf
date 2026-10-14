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

variable "eventhub_capacity" {
  description = "Throughput units do namespace Event Hubs (Standard)."
  type        = number
  default     = 1
}

variable "aks_node_vm_size" {
  description = "SKU do nó do AKS. Na Students, o AKS só aceita famílias D/E/F v3+ e só DSv3 tem cota (4 vCPUs)."
  type        = string
  default     = "Standard_D2s_v3"
}

variable "aks_node_count" {
  description = "Quantidade de nós do pool de sistema."
  type        = number
  default     = 1
}

variable "postgres_location" {
  description = "Região do Postgres. Na Students, Flexible Server é bloqueado em eastus2/southcentralus."
  type        = string
  default     = "canadacentral"
}

variable "postgres_sku" {
  description = "SKU do Postgres Flexible Server."
  type        = string
  default     = "B_Standard_B1ms"
}

variable "postgres_human_admins" {
  description = "Administradores Entra humanos do Postgres: UPN -> object id."
  type        = map(string)
  default     = {}
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
