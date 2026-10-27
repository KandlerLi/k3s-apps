# Generated here, not in Secrets Manager: nobody types them. Rotating the key logs everyone out.

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
    namespace = "apps"
    name      = "paperless-postgres"
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
    namespace = "apps"
    name      = "paperless-env"
  }

  data = {
    PAPERLESS_DBPASS     = random_password.postgres.result
    PAPERLESS_SECRET_KEY = random_password.secret_key.result
    # client_secret_basic and PKCE, matching modules/authelia's paperless client.
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
