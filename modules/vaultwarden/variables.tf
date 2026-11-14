variable "authelia_oidc_client_secret" {
  description = <<-EOT
    Plaintext half of Vaultwarden's Authelia OIDC client secret pair --
    Authelia holds the matching hash (modules/authelia's
    authelia_oidc_vaultwarden_client_secret_hash). Sourced from AWS
    Secrets Manager's k3s-apps/vaultwarden group (secrets.tf).
  EOT
  type        = string
  sensitive   = true
}
