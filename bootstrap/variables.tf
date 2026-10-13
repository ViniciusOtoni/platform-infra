variable "subscription_id" {
  description = "Subscription Azure onde a plataforma será criada."
  type        = string
}

variable "location" {
  description = "Região do storage de tfstate."
  type        = string
  default     = "eastus2"
}

variable "tfstate_storage_account_name" {
  description = "Nome global e único do storage account do tfstate (3-24 caracteres minúsculos/dígitos)."
  type        = string
  default     = "sttfedpviniciusotoni"
}

variable "github_owner" {
  description = "Owner (usuário/organização) dos repositórios no GitHub."
  type        = string
  default     = "ViniciusOtoni"
}

variable "github_identities" {
  description = <<-EOT
    Identidades OIDC por papel -> lista de subjects "<repo>:<qualificador>".
    Qualificadores: "pull_request", "environment:<env>", "ref:refs/heads/<branch>".
    Limite: 20 federated credentials por App Registration.
  EOT
  type        = map(list(string))
  default = {
    infra = [
      "platform-infra:pull_request",
      "platform-infra:environment:dev",
    ]
    deployer = [
      "pedidos-service:environment:dev",
      "pedidos-service:environment:prd",
      "pedidos-data:pull_request",
      "pedidos-data:environment:dev",
    ]
  }

  validation {
    condition     = contains(keys(var.github_identities), "infra") && contains(keys(var.github_identities), "deployer")
    error_message = "github_identities deve conter as chaves \"infra\" e \"deployer\"."
  }
}
