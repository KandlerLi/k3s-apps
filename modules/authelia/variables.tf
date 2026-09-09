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

variable "authelia_oidc_hmac_secret" {
  description = <<-EOT
    Random, opaque signing secret for Authelia's own OIDC provider
    (config's identity_providers.oidc.hmac_secret) -- pure random
    noise, not a password anyone types or needs to remember. Generated
    with: authelia crypto rand --length 64 --charset alphanumeric.
    Same value as home-infra's authelia_oidc_hmac_secret SOPS secret.
    Pass via TF_VAR_authelia_oidc_hmac_secret at apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "authelia_oidc_issuer_private_key" {
  description = <<-EOT
    RSA private key (PEM, 4096-bit) Authelia's OIDC provider signs
    tokens with (config's identity_providers.oidc.jwks). Generated
    with: authelia crypto pair rsa generate -b 4096. Same value as
    home-infra's authelia_oidc_issuer_private_key SOPS secret. Pass
    via TF_VAR_authelia_oidc_issuer_private_key at apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "authelia_oidc_grafana_client_secret_hash" {
  description = <<-EOT
    pbkdf2-sha512 hash of Grafana's own OIDC client secret (config's
    identity_providers.oidc.clients[].client_secret for the "grafana"
    client) -- only the hash lives here, the plaintext goes to
    modules/grafana's own variable of a similar name instead, since
    that's the side that actually presents it. Generated together
    with: authelia crypto hash generate pbkdf2 --variant sha512
    --random --random.length 64 --random.charset alphanumeric. Same
    value as home-infra's authelia_oidc_grafana_client_secret_hash
    SOPS secret. Pass via
    TF_VAR_authelia_oidc_grafana_client_secret_hash at apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "authelia_oidc_openwebui_client_secret_hash" {
  description = <<-EOT
    pbkdf2-sha512 hash of Open WebUI's own OIDC client secret (config's
    identity_providers.oidc.clients[].client_secret for the
    "open-webui" client) -- only the hash lives here, the plaintext
    goes to modules/open_webui's own variable of a similar name
    instead, since that's the side that actually presents it.
    Generated the same way as the Grafana client secret hash above.
    Same value as home-infra's
    authelia_oidc_openwebui_client_secret_hash SOPS secret. Pass via
    TF_VAR_authelia_oidc_openwebui_client_secret_hash at apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "authelia_oidc_nextcloud_client_secret_hash" {
  description = <<-EOT
    pbkdf2-sha512 hash of Nextcloud's own OIDC client secret (config's
    identity_providers.oidc.clients[].client_secret for the
    "nextcloud" client) -- only the hash lives here. Unlike Grafana/
    Open WebUI, the matching plaintext never flows through this repo
    at all -- Nextcloud AIO runs on the homeserver
    (infra/home-infra's own nextcloud_aio role), not in k3s, so the
    plaintext goes straight into home-infra's own SOPS vault for
    Ansible to read directly, no TF_VAR_/CI wiring needed for that
    side. Generated the same way as the Grafana/Open WebUI client
    secret hashes. Same value as home-infra's
    authelia_oidc_nextcloud_client_secret_hash SOPS secret. Pass via
    TF_VAR_authelia_oidc_nextcloud_client_secret_hash at apply time.
  EOT
  type        = string
  sensitive   = true
}
