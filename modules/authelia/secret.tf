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

      # OIDC provider, added 2026-09-08 -- lets Grafana, Open WebUI, and
      # (2026-09-09) Nextcloud authenticate against Authelia directly (a
      # real "Sign in with Authelia" button, not just the ingress-level
      # forwardAuth gate already in front of Grafana/the agent
      # API/torrent/home/k8s-dashboard) instead of each keeping only
      # its own separate native login. Grafana and Open WebUI have
      # since had native login disabled entirely (see their own
      # modules) once it was confirmed live that it silently skipped
      # Authelia's own MFA requirement -- Nextcloud deliberately keeps
      # native login enabled, since it may have other real accounts
      # (family, other technical users) not necessarily tied to this
      # same Authelia identity.
      identity_providers:
        oidc:
          hmac_secret: '${var.authelia_oidc_hmac_secret}'
          jwks:
            - key_id: 'main'
              algorithm: 'RS256'
              use: 'sig'
              # A double-quoted, single-physical-line scalar with
              # escaped \n sequences -- not a YAML literal block
              # scalar (key: |), deliberately. Confirmed live (locally,
              # against the real interpolation): combining Terraform's
              # own heredoc dedent with a multi-line interpolated
              # value produces genuinely inconsistent per-line
              # indentation (the PEM's first line landed at a
              # different column than every line after it), which a
              # YAML block scalar would then fold into the parsed
              # value as stray literal whitespace, corrupting the key.
              # replace()+escaped-\n sidesteps the whole class of bug
              # -- one physical line has no indentation to get wrong,
              # and round-trips byte-for-byte through a real YAML
              # parser (verified with a standalone test before using
              # this here).
              key: "${replace(var.authelia_oidc_issuer_private_key, "\n", "\\n")}"
          # Confirmed live, 2026-09-09: Authelia 4.39 deliberately keeps
          # the ID Token near-empty by default (see the "resolved" note
          # below on why that's not itself the bug) -- real claims
          # (groups included) live on the UserInfo response instead,
          # confirmed correct via `authelia debug oidc claims`. Grafana
          # is documented to fall through to UserInfo for
          # role_attribute_path if the ID Token lacks the claim, but a
          # confirmed, open Grafana bug (grafana/grafana#106686) means
          # it never actually does that in practice -- role_attribute_path
          # only ever gets evaluated against the ID Token, so groups
          # from UserInfo are silently ignored and every login lands as
          # Viewer regardless of real group membership. Grafana's own
          # debug logs showed this exactly: "Groups: [admins]" correctly
          # extracted, "Role: Viewer" anyway. Worked around here, not in
          # Grafana (nothing to configure on that side that would fix
          # it) -- putting groups back into the ID Token directly
          # sidesteps Grafana's broken fallback entirely.
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
              # Not confirmed broken for Open WebUI the way it is for
              # Grafana (grafana/grafana#106686), but applying the same
              # policy here too is harmless and pre-empts hitting the
              # same class of issue.
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
              # Nextcloud's own documented client_secret_post
              # requirement (its own user_oidc app's own integration
              # guide) -- different from Grafana/Open WebUI's
              # client_secret_basic above, confirmed against Authelia's
              # own official Nextcloud integration guide, not assumed
              # to match the other two.
              token_endpoint_auth_method: 'client_secret_post'
              # Same unsigned-response pattern as Grafana's own client
              # -- Authelia's own Nextcloud integration guide
              # recommends this too.
              access_token_signed_response_alg: 'none'
              userinfo_signed_response_alg: 'none'

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
