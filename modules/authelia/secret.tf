# Both files below are wholly credential-bearing (every secret
# Authelia needs is inlined directly into its own YAML, the same shape
# Authelia's own docs assume for a single-file deployment) -- Secrets,
# never ConfigMaps, matching modules/blocky's own config.yml precedent
# for exactly the same reason.

# auth.jkandler.de is bypass -- the login portal has to be reachable to
# unauthenticated users, or nobody could ever log in.
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
              - 'mail.jkandler.de'
              - 'stalwart.jkandler.de'
            policy: two_factor

      # OIDC provider -- lets Grafana, Open WebUI, Nextcloud, and Bulwark
      # authenticate against Authelia directly (a real "Sign in with
      # Authelia" button), in addition to the ingress-level forwardAuth
      # gate most of them also sit behind. See current-state.md ("k3s
      # learning cluster", Authelia SSO entry) for per-client gotchas.
      identity_providers:
        oidc:
          hmac_secret: '${var.authelia_oidc_hmac_secret}'
          jwks:
            - key_id: 'main'
              algorithm: 'RS256'
              use: 'sig'
              # A double-quoted, single-physical-line scalar with
              # escaped \n sequences, not a YAML block scalar -- see
              # current-state.md for why a block scalar corrupts this.
              key: "${replace(var.authelia_oidc_issuer_private_key, "\n", "\\n")}"
          # Grafana's own role_attribute_path only ever evaluates
          # against the ID Token (grafana/grafana#106686) -- see
          # current-state.md.
          claims_policies:
            groups_in_id_token:
              id_token:
                - 'groups'
                - 'email'
                - 'email_verified'
                - 'preferred_username'
          clients:
            - client_id: 'grafana'
              client_name: 'Grafana'
              client_secret: '${var.authelia_oidc_grafana_client_secret_hash}'
              public: false
              authorization_policy: 'two_factor'
              claims_policy: 'groups_in_id_token'
              require_pkce: true
              pkce_challenge_method: 'S256'
              redirect_uris:
                - 'https://grafana.jkandler.de/login/generic_oauth'
              scopes:
                - 'openid'
                - 'profile'
                - 'groups'
                - 'email'
              response_types:
                - 'code'
              grant_types:
                - 'authorization_code'
              token_endpoint_auth_method: 'client_secret_basic'
              # Grafana's own documented claims-hydration limitation --
              # Authelia's own Grafana integration guide recommends
              # unsigned (plain JSON) responses specifically for this
              # client, not a general requirement for every client.
              access_token_signed_response_alg: 'none'
              userinfo_signed_response_alg: 'none'
            - client_id: 'open-webui'
              client_name: 'Open WebUI'
              client_secret: '${var.authelia_oidc_openwebui_client_secret_hash}'
              public: false
              authorization_policy: 'two_factor'
              claims_policy: 'groups_in_id_token'
              require_pkce: true
              pkce_challenge_method: 'S256'
              redirect_uris:
                - 'https://ai.jkandler.de/oauth/oidc/callback'
              scopes:
                - 'openid'
                - 'profile'
                - 'groups'
                - 'email'
              response_types:
                - 'code'
              grant_types:
                - 'authorization_code'
              token_endpoint_auth_method: 'client_secret_basic'
            # Bulwark's own "sign in with Authelia" button -- does NOT
            # by itself change how Bulwark authenticates to Stalwart's
            # JMAP endpoint underneath (see modules/bulwark's own
            # comment). redirect_uris only covers the two locales
            # listed -- add another if a different one 404s.
            - client_id: 'bulwark'
              client_name: 'Bulwark Webmail'
              client_secret: '${var.authelia_oidc_bulwark_client_secret_hash}'
              public: false
              authorization_policy: 'two_factor'
              claims_policy: 'groups_in_id_token'
              require_pkce: true
              pkce_challenge_method: 'S256'
              redirect_uris:
                - 'https://mail.jkandler.de/de/auth/callback'
                - 'https://mail.jkandler.de/en/auth/callback'
              scopes:
                - 'openid'
                - 'profile'
                - 'groups'
                - 'email'
              response_types:
                - 'code'
              grant_types:
                - 'authorization_code'
              # Bulwark sends the client secret in the POST body, like
              # Nextcloud below, not the Authorization header
              # Grafana/Open WebUI use.
              token_endpoint_auth_method: 'client_secret_post'
            - client_id: 'nextcloud'
              client_name: 'Nextcloud'
              client_secret: '${var.authelia_oidc_nextcloud_client_secret_hash}'
              public: false
              authorization_policy: 'two_factor'
              claims_policy: 'groups_in_id_token'
              require_pkce: true
              pkce_challenge_method: 'S256'
              redirect_uris:
                - 'https://nextcloud.jkandler.de/apps/user_oidc/code'
              scopes:
                - 'openid'
                - 'profile'
                - 'groups'
                - 'email'
              response_types:
                - 'code'
              grant_types:
                - 'authorization_code'
              token_endpoint_auth_method: 'client_secret_post'
              access_token_signed_response_alg: 'none'
              userinfo_signed_response_alg: 'none'

      session:
        secret: '${var.authelia_session_secret}'
        cookies:
          - domain: 'jkandler.de'
            authelia_url: 'https://auth.jkandler.de'
            default_redirection_url: 'https://home.jkandler.de'
        # Without this block Authelia keeps sessions in process memory
        # only, so every Pod restart (each rollout) logged everyone
        # out. Redis is a sidecar in this same Pod (main.tf), so
        # 127.0.0.1 is enough and it is not reachable from other Pods.
        redis:
          host: '127.0.0.1'
          port: 6379

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
        # A second, separate identity purely so Stalwart's own "admin"
        # account can SSO through Authelia too -- see current-state.md's
        # mail server section.
        admin:
          disabled: false
          displayname: 'Stalwart Admin'
          password: '${var.authelia_stalwart_admin_password_hash}'
          email: 'julian.kandler@outlook.com'
          groups:
            - admins
    EOT
  }

  type = "Opaque"
}
