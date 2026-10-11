# Injected via secret_key_ref: OAUTH_CLIENT_SECRET has no _FILE convention.
resource "kubernetes_secret_v1" "open_webui_oidc_client_secret" {
  metadata {
    name = "open-webui-oidc-client-secret"
  }

  data = {
    OAUTH_CLIENT_SECRET = var.authelia_oidc_openwebui_client_secret
  }

  type = "Opaque"
}
