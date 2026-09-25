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
