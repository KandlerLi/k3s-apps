resource "kubernetes_secret_v1" "vaultwarden_sso" {
  metadata {
    namespace = "apps"
    name      = "vaultwarden-sso"
  }

  data = {
    SSO_CLIENT_SECRET = var.authelia_oidc_client_secret
  }

  type = "Opaque"
}
