variable "initial_signup" {
  description = <<-EOT
    true only while the first account is created: signups are open and
    every route, the client API included, sits behind Authelia. false
    closes signups and makes the client API public (ADR 0028), so open
    signups are never reachable without Authelia.
  EOT
  type        = bool
}

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
