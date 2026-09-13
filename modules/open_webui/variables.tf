variable "authelia_oidc_openwebui_client_secret" {
  description = <<-EOT
    Plaintext OIDC client secret this Open WebUI instance presents to
    Authelia's token endpoint when a user signs in via "Sign in with
    Authelia" -- Authelia's own config (modules/authelia) verifies
    against a pbkdf2 hash of this same value, never the plaintext
    itself. Sourced directly from AWS Secrets Manager's
    home-infra/open-webui group (secrets.tf's
    local.home_infra_open_webui["authelia_oidc_openwebui_client_secret"]).
  EOT
  type        = string
  sensitive   = true
}
