variable "authelia_oidc_openwebui_client_secret" {
  description = <<-EOT
    Plaintext OIDC client secret this Open WebUI instance presents to
    Authelia's token endpoint when a user signs in via "Sign in with
    Authelia" -- Authelia's own config (modules/authelia) verifies
    against a pbkdf2 hash of this same value, never the plaintext
    itself. Same value as home-infra's
    authelia_oidc_openwebui_client_secret SOPS secret. Pass via
    TF_VAR_authelia_oidc_openwebui_client_secret at apply time.
  EOT
  type        = string
  sensitive   = true
}
