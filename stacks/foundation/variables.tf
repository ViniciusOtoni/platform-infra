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
  description = "Região Azure (a subscription Students permite: eastus2, canadacentral, southcentralus, mexicocentral, chilecentral)."
  type        = string
  default     = "eastus2"
}

variable "deployer_principal_id" {
  description = "Principal ID da identidade deployer (output deployer_object_id do bootstrap). Recebe AcrPush."
  type        = string
}
