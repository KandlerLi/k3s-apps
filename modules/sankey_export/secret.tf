# Shape lives in modules/ghcr_pull_secret -- shared with
# modules/home_agent/secret.tf.
moved {
  from = kubernetes_secret_v1.ghcr_pull
  to   = module.ghcr_pull_secret.kubernetes_secret_v1.this
}

module "ghcr_pull_secret" {
  source = "../ghcr_pull_secret"

  name  = "sankey-export-ghcr-pull-secret"
  token = var.sankey_export_ghcr_token
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
