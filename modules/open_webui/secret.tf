# Injected via env.value_from.secret_key_ref in main.tf, not a
# mounted _FILE path the way modules/grafana's own OIDC client secret
# is -- Open WebUI's own OAUTH_CLIENT_SECRET env var has no confirmed
# "_FILE suffix" convention the way Grafana's GF_* vars generically do,
# so this uses the plain Kubernetes-native secret injection instead,
# which needs no app-level support at all.
resource "kubernetes_secret_v1" "open_webui_oidc_client_secret" {
  metadata {
    name = "open-webui-oidc-client-secret"
  }

  data = {
    OAUTH_CLIENT_SECRET = var.authelia_oidc_openwebui_client_secret
  }

  type = "Opaque"
}
