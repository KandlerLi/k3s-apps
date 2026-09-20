variable "authelia_session_secret" {
  description = <<-EOT
    Random, opaque encryption key for Authelia's own session cookies
    (config's session.secret) -- pure random noise, not a password
    anyone types or needs to remember. Sourced directly from AWS
    Secrets Manager's home-infra/authelia group (secrets.tf's
    local.home_infra_authelia["authelia_session_secret"]).
  EOT
  type        = string
  sensitive   = true
}

variable "authelia_storage_encryption_key" {
  description = <<-EOT
    Encryption key for Authelia's own SQLite storage (config's
    storage.encryption_key) -- encrypts session/TOTP-registration state
    at rest inside the database file. Sourced directly from AWS
    Secrets Manager's home-infra/authelia group (secrets.tf's
    local.home_infra_authelia["authelia_storage_encryption_key"]).
  EOT
  type        = string
  sensitive   = true
}

variable "authelia_reset_password_jwt_secret" {
  description = <<-EOT
    Signing secret for the password-reset email's JWT link (config's
    identity_validation.reset_password.jwt_secret). Sourced directly
    from AWS Secrets Manager's home-infra/authelia group (secrets.tf's
    local.home_infra_authelia["authelia_reset_password_jwt_secret"]).
  EOT
  type        = string
  sensitive   = true
}

variable "authelia_admin_password_hash" {
  description = <<-EOT
    Argon2id hash of Julian's own Authelia login password (the file
    authentication_backend's users_database.yml) -- plaintext stays in
    the password manager, only the hash lives here. Generated with:
      docker run --rm authelia/authelia:4.39.22 \
        authelia crypto hash generate argon2 --password '<password>'
    Sourced directly from AWS Secrets Manager's home-infra/authelia
    group (secrets.tf's
    local.home_infra_authelia["authelia_admin_password_hash"]).
  EOT
  type        = string
  sensitive   = true
}

variable "alertmanager_ses_smtp_username" {
  description = <<-EOT
    Same SES SMTP identity Alertmanager already uses (see
    modules/alertmanager's own variable of the same name) -- reused
    here for Authelia's own password-reset notification emails rather
    than provisioning a second SMTP identity. Sourced directly from AWS
    Secrets Manager's home-infra/monitoring group (secrets.tf's
    local.home_infra_monitoring["monitoring_ses_smtp_username"]).
  EOT
  type        = string
  sensitive   = true
}

variable "alertmanager_ses_smtp_password" {
  description = <<-EOT
    Same SES SMTP identity Alertmanager already uses (see
    modules/alertmanager's own variable of the same name) -- reused
    here for Authelia's own password-reset notification emails rather
    than provisioning a second SMTP identity. Sourced directly from AWS
    Secrets Manager's home-infra/monitoring group (secrets.tf's
    local.home_infra_monitoring["monitoring_ses_smtp_password"]).
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
    Sourced directly from AWS Secrets Manager's home-infra/authelia
    group (secrets.tf's
    local.home_infra_authelia["authelia_oidc_hmac_secret"]).
  EOT
  type        = string
  sensitive   = true
}

variable "authelia_oidc_issuer_private_key" {
  description = <<-EOT
    RSA private key (PEM, 4096-bit) Authelia's OIDC provider signs
    tokens with (config's identity_providers.oidc.jwks). Generated
    with: authelia crypto pair rsa generate -b 4096. Sourced directly
    from AWS Secrets Manager's home-infra/authelia group (secrets.tf's
    local.home_infra_authelia["authelia_oidc_issuer_private_key"]).
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
    --random --random.length 64 --random.charset alphanumeric. Sourced
    directly from AWS Secrets Manager's home-infra/authelia group
    (secrets.tf's
    local.home_infra_authelia["authelia_oidc_grafana_client_secret_hash"]).
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
    Sourced directly from AWS Secrets Manager's home-infra/authelia
    group (secrets.tf's
    local.home_infra_authelia["authelia_oidc_openwebui_client_secret_hash"]).
  EOT
  type        = string
  sensitive   = true
}

variable "authelia_oidc_bulwark_client_secret_hash" {
  description = <<-EOT
    pbkdf2-sha512 hash of Bulwark webmail's own OIDC client secret
    (config's identity_providers.oidc.clients[].client_secret for the
    "bulwark" client) -- only the hash lives here, the plaintext goes
    to modules/bulwark's own variable of a similar name instead, since
    that's the side that actually presents it. Generated the same way
    as the Grafana client secret hash above. Sourced directly from AWS
    Secrets Manager's home-infra/authelia group (secrets.tf's
    local.home_infra_authelia["authelia_oidc_bulwark_client_secret_hash"]).
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
    plaintext lives in AWS Secrets Manager's own home-infra/nextcloud
    group instead, read directly by Ansible's
    amazon.aws.secretsmanager_secret lookup, no TF_VAR_/CI wiring
    needed for that side. Generated the same way as the Grafana/Open
    WebUI client secret hashes. Sourced directly from AWS Secrets
    Manager's home-infra/authelia group (secrets.tf's
    local.home_infra_authelia["authelia_oidc_nextcloud_client_secret_hash"]).
  EOT
  type        = string
  sensitive   = true
}
