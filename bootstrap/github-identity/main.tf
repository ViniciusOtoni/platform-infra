# App Registration + Service Principal + federated credentials para GitHub Actions (OIDC).

terraform {
  required_providers {
    azuread = {
      source = "hashicorp/azuread"
    }
  }
}

variable "display_name" {
  type = string
}

variable "github_owner" {
  type = string
}

variable "subjects" {
  description = "Lista \"<repo>:<qualificador>\"."
  type        = list(string)
}

resource "azuread_application" "this" {
  display_name = var.display_name
}

resource "azuread_service_principal" "this" {
  client_id = azuread_application.this.client_id
}

resource "azuread_application_federated_identity_credential" "this" {
  for_each = toset(var.subjects)

  application_id = azuread_application.this.id
  # Nome: apenas [a-zA-Z0-9-_]; derivado do subject.
  display_name = substr(replace(each.value, "/[^a-zA-Z0-9-]/", "-"), 0, 120)
  audiences    = ["api://AzureADTokenExchange"]
  issuer       = "https://token.actions.githubusercontent.com"
  subject      = "repo:${var.github_owner}/${each.value}"
}

output "client_id" {
  value = azuread_application.this.client_id
}

output "object_id" {
  description = "Object ID do Service Principal (para role assignments)."
  value       = azuread_service_principal.this.object_id
}
