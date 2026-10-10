variable "paperless_oidc_client_secret" {
  description = <<-EOT
    Plaintext half of Paperless-ngx's Authelia OIDC client secret pair --
    Authelia holds the matching hash (modules/authelia's
    authelia_oidc_paperless_client_secret_hash). Sourced from AWS
    Secrets Manager's k3s-apps/paperless group (secrets.tf).
  EOT
  type        = string
  sensitive   = true
}

variable "outlook_oauth_client_id" {
  description = <<-EOT
    Client ID of the Microsoft app registration for Outlook mail OAuth2
    (ADR 0023, update 2026-09-27). Empty disables Outlook mail login.
    Sourced from AWS Secrets Manager's k3s-apps/paperless group.
  EOT
  type        = string
  default     = ""
}

variable "outlook_oauth_client_secret" {
  description = "Client secret (value) of the same Microsoft app registration. Empty disables Outlook mail login."
  type        = string
  default     = ""
  sensitive   = true
}
