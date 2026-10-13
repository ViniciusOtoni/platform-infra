variable "subscription_id" {
  description = "Subscription Azure da plataforma."
  type        = string
}

variable "environment" {
  description = "Nome do ambiente (dev, prd)."
  type        = string

  validation {
    condition     = contains(["dev", "prd"], var.environment)
    error_message = "environment deve ser dev ou prd."
  }
}

variable "location" {
  description = "Região Azure."
  type        = string
  default     = "eastus2"
}

variable "deployer_principal_id" {
  description = "Object ID do SP deployer (output deployer_object_id do bootstrap). Recebe AcrPush."
  type        = string
}

variable "aks_node_vm_size" {
  description = "SKU do nó do AKS (pool de sistema, 1 nó em dev)."
  type        = string
  default     = "Standard_D2as_v5"
}

variable "aks_node_count" {
  description = "Quantidade de nós do pool de sistema."
  type        = number
  default     = 1
}

variable "eventhub_capacity" {
  description = "Throughput units do namespace Event Hubs (Standard)."
  type        = number
  default     = 1
}
