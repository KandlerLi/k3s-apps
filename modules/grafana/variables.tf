variable "blocky_postgres_password" {
  description = <<-EOT
    Password for the blocky-postgresql datasource's read access to
    Blocky's query-log database, reached over modules/blocky's own
    in-cluster Service now (blocky-svc:5432). Sourced directly from
    AWS Secrets Manager's home-infra/blocky group (secrets.tf's
    local.home_infra_blocky["blocky_postgres_password"]).
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
    itself. Sourced directly from AWS Secrets Manager's
    home-infra/grafana group (secrets.tf's
    local.home_infra_grafana["authelia_oidc_grafana_client_secret"]).
  EOT
  type        = string
  sensitive   = true
}
