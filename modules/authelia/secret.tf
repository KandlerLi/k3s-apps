# Both files below are wholly credential-bearing (every secret
# Authelia needs is inlined directly into its own YAML, the same shape
# Authelia's own docs assume for a single-file deployment) -- Secrets,
# never ConfigMaps, matching modules/blocky's own config.yml precedent
# for exactly the same reason.

# access_control gates every currently Basic-Auth-gated hostname with
# two_factor already, in the same apply that first stands this Pod up
# -- but modules/ingress/configmap.tf itself still points every one of
# those chains at the old shared-auth (Basic Auth) middleware, not at
# this Authelia instance, until the deliberate, separate cutover step
# (see that module's own comment). Configuring the policy here now,
# ahead of Traefik ever actually calling out to it, is harmless: with
# no forwardAuth middleware referencing this Pod yet, these rules are
# simply unevaluated. auth.jkandler.de itself is bypass -- the login
# portal has to be reachable to unauthenticated users, or nobody could
# ever log in.
resource "kubernetes_secret_v1" "authelia_config" {
  metadata {
    name = "authelia-config"
  }

  data = {
    "configuration.yml" = <<-EOT
      server:
        address: 'tcp://0.0.0.0:9091'

      log:
        level: 'info'

      totp:
        issuer: 'jkandler.de'

      identity_validation:
        reset_password:
          jwt_secret: '${var.authelia_reset_password_jwt_secret}'

      authentication_backend:
        file:
          path: /config/users_database.yml

      access_control:
        default_policy: deny
        rules:
          - domain: 'auth.jkandler.de'
            policy: bypass
          - domain:
              - 'ai.jkandler.de'
              - 'torrent.jkandler.de'
              - 'grafana.jkandler.de'
              - 'home.jkandler.de'
              - 'k8s.jkandler.de'
            policy: two_factor

      session:
        secret: '${var.authelia_session_secret}'
        cookies:
          - domain: 'jkandler.de'
            authelia_url: 'https://auth.jkandler.de'
            default_redirection_url: 'https://home.jkandler.de'

      storage:
        encryption_key: '${var.authelia_storage_encryption_key}'
        local:
          path: /data/db.sqlite3

      # SES's own sandbox-mode single-verified-recipient limit (see
      # aws/ses-relay's own variables.tf) is why startup_check_address
      # and every real recipient this ever sends to has to stay
      # julian.kandler@outlook.com -- the same address
      # modules/alertmanager's own alert_email already uses.
      notifier:
        smtp:
          address: 'submission://email-smtp.eu-central-1.amazonaws.com:587'
          username: '${var.alertmanager_ses_smtp_username}'
          password: '${var.alertmanager_ses_smtp_password}'
          sender: 'auth@jkandler.de'
          identifier: 'jkandler.de'
          startup_check_address: 'julian.kandler@outlook.com'
    EOT
  }

  type = "Opaque"
}

# The file authentication_backend's own user database -- one user,
# argon2id-hashed (Authelia's own default algorithm/parameters, not
# overridden above). See variables.tf's own comment on
# authelia_admin_password_hash for exactly how this hash is generated.
resource "kubernetes_secret_v1" "authelia_users" {
  metadata {
    name = "authelia-users"
  }

  data = {
    "users_database.yml" = <<-EOT
      users:
        julian:
          disabled: false
          displayname: 'Julian'
          password: '${var.authelia_admin_password_hash}'
          email: 'julian.kandler@outlook.com'
          groups:
            - admins
    EOT
  }

  type = "Opaque"
}
