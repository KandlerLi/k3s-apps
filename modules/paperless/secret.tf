# The secret key and the database password are generated here, not kept
# in Secrets Manager: nobody ever types either (see
# aws/secrets-manager's runbooks/k3s-apps/paperless.md). Rotating the
# secret key logs everyone out and invalidates API tokens.

resource "random_password" "secret_key" {
  length  = 64
  special = false
}

resource "random_password" "postgres" {
  length  = 40
  special = false
}

resource "kubernetes_secret_v1" "paperless_postgres" {
  metadata {
    name = "paperless-postgres"
  }

  data = {
    POSTGRES_USER     = "paperless"
    POSTGRES_DB       = "paperless"
    POSTGRES_PASSWORD = random_password.postgres.result
  }

  type = "Opaque"
}

resource "kubernetes_secret_v1" "paperless_env" {
  metadata {
    name = "paperless-env"
  }

  data = {
    PAPERLESS_DBPASS     = random_password.postgres.result
    PAPERLESS_SECRET_KEY = random_password.secret_key.result
    # client_secret_basic and PKCE on both sides, matching the
    # "paperless" client in modules/authelia.
    PAPERLESS_SOCIALACCOUNT_PROVIDERS = jsonencode({
      openid_connect = {
        SCOPE              = ["openid", "profile", "email", "groups"]
        OAUTH_PKCE_ENABLED = true
        APPS = [{
          provider_id = "authelia"
          name        = "Authelia"
          client_id   = "paperless"
          secret      = var.paperless_oidc_client_secret
          settings = {
            server_url        = "https://auth.jkandler.de"
            token_auth_method = "client_secret_basic"
          }
        }]
      }
    })
  }

  type = "Opaque"
}
