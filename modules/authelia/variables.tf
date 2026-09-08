variable "authelia_session_secret" {
  description = <<-EOT
    Random, opaque encryption key for Authelia's own session cookies
    (config's session.secret) -- pure random noise, not a password
    anyone types or needs to remember. Same value as home-infra's
    authelia_session_secret SOPS secret. Pass via
    TF_VAR_authelia_session_secret at apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "authelia_storage_encryption_key" {
  description = <<-EOT
    Encryption key for Authelia's own SQLite storage (config's
    storage.encryption_key) -- encrypts session/TOTP-registration state
    at rest inside the database file. Same value as home-infra's
    authelia_storage_encryption_key SOPS secret. Pass via
    TF_VAR_authelia_storage_encryption_key at apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "authelia_reset_password_jwt_secret" {
  description = <<-EOT
    Signing secret for the password-reset email's JWT link (config's
    identity_validation.reset_password.jwt_secret). Same value as
    home-infra's authelia_reset_password_jwt_secret SOPS secret. Pass
    via TF_VAR_authelia_reset_password_jwt_secret at apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "authelia_admin_password_hash" {
  description = <<-EOT
    Argon2id hash of Julian's own Authelia login password (the file
    authentication_backend's users_database.yml) -- same
    plaintext-stays-in-the-password-manager, only-the-hash-in-SOPS
    convention as home-infra's shared_ingress_auth_password_hash.
    Generated with:
      docker run --rm authelia/authelia:4.39.22 \
        authelia crypto hash generate argon2 --password '<password>'
    Same value as home-infra's authelia_admin_password_hash SOPS
    secret. Pass via TF_VAR_authelia_admin_password_hash at apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "alertmanager_ses_smtp_username" {
  description = <<-EOT
    Same SES SMTP identity Alertmanager already uses (see
    modules/alertmanager's own variable of the same name) -- reused
    here for Authelia's own password-reset notification emails rather
    than provisioning a second SMTP identity. Same value as
    home-infra's monitoring_ses_smtp_username SOPS secret. Pass via
    TF_VAR_alertmanager_ses_smtp_username at apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "alertmanager_ses_smtp_password" {
  description = <<-EOT
    Same SES SMTP identity Alertmanager already uses (see
    modules/alertmanager's own variable of the same name) -- reused
    here for Authelia's own password-reset notification emails rather
    than provisioning a second SMTP identity. Same value as
    home-infra's monitoring_ses_smtp_password SOPS secret. Pass via
    TF_VAR_alertmanager_ses_smtp_password at apply time.
  EOT
  type        = string
  sensitive   = true
}
