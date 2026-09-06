# sankey-export's own image is a private GHCR package
# (ghcr.io/kandlerli/sankey-export), same shape as home_agent's own
# ghcr_pull secret -- a separate copy because kubernetes_secret_v1 is
# module-local here (see modules/home_agent/secret.tf's own comment);
# nothing shares one across modules in this repo yet.
resource "kubernetes_secret_v1" "ghcr_pull" {
  metadata {
    name = "sankey-export-ghcr-pull-secret"
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = "KandlerLi"
          password = var.sankey_export_ghcr_token
          auth     = base64encode("KandlerLi:${var.sankey_export_ghcr_token}")
        }
      }
    })
  }
}

# Mounted at SANKEY_EXPORT_APP_PASSWORD_FILE's own default path
# (/etc/sankey-export/app-password), matching the _FILE convention
# home-infra's own Ansible deployment already uses.
resource "kubernetes_secret_v1" "sankey_export_app_password" {
  metadata {
    name = "sankey-export-app-password"
  }

  data = {
    "app-password" = var.sankey_export_app_password
  }

  type = "Opaque"
}
