variable "blocky_postgres_password" {
  description = <<-EOT
    Password for the blocky-postgresql datasource's read access to
    Blocky's query-log database, reached over modules/blocky's own
    in-cluster Service now (blocky-svc:5432). Same value as
    home-infra's blocky_postgres_password SOPS secret -- pass it via
    TF_VAR_blocky_postgres_password at apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "authelia_oidc_grafana_client_secret" {
  description = <<-EOT
    Plaintext OIDC client secret this Grafana instance presents to
    Authelia's token endpoint when a user signs in via "Sign in with
    Authelia" -- Authelia's own config (modules/authelia) verifies
    against a pbkdf2 hash of this same value, never the plaintext
    itself. Same value as home-infra's
    authelia_oidc_grafana_client_secret SOPS secret. Pass via
    TF_VAR_authelia_oidc_grafana_client_secret at apply time.
  EOT
  type        = string
  sensitive   = true
}
