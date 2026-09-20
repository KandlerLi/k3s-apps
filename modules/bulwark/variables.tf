variable "bulwark_oidc_client_secret" {
  description = <<-EOT
    Plaintext half of Bulwark's Authelia OIDC client secret pair --
    Authelia holds the matching pbkdf2-sha512 hash
    (modules/authelia's own authelia_oidc_bulwark_client_secret_hash).
    Sourced directly from AWS Secrets Manager's k3s-apps/bulwark group
    (secrets.tf's
    local.k3s_apps_bulwark["authelia_oidc_bulwark_client_secret"]).
  EOT
  type        = string
  sensitive   = true
}
