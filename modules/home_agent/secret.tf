# home-agent's own image is a private GHCR package (ghcr.io/kandlerli/
# home-agent) -- this is what lets the cluster actually pull it.
# Read-scoped only: this credential never needs write:packages, unlike
# the token a human uses to push (see home-infra's build-home-agent.yml,
# which uses the workflow's own short-lived GITHUB_TOKEN for that
# instead of any durable credential).
#
# Shape lives in modules/ghcr_pull_secret -- shared with
# modules/sankey_export/secret.tf.
moved {
  from = kubernetes_secret_v1.ghcr_pull
  to   = module.ghcr_pull_secret.kubernetes_secret_v1.this
}

module "ghcr_pull_secret" {
  source = "../ghcr_pull_secret"

  name  = "ghcr-pull-secret"
  token = var.home_agent_ghcr_token
}

# Mounted into the home-agent container at /run/secrets/openai, matching
# OPENAI_API_KEY_FILE's own default path in api.py -- same _FILE
# convention home-infra's own Ansible deployment already uses, rather
# than a raw env var. Now only Whisper STT (audio.py) reads this one;
# chat moved to anthropic_api_key below 2026-09-18.
resource "kubernetes_secret_v1" "openai_api_key" {
  metadata {
    name = "home-agent-openai-api-key"
  }

  data = {
    "openai_api_key" = var.home_agent_openai_api_key
  }

  type = "Opaque"
}

# Mounted into the home-agent container at /run/secrets/anthropic,
# matching ANTHROPIC_API_KEY_FILE's own default path in api.py -- same
# _FILE convention, separate mount path from openai_api_key above so
# both Secrets can be volume-mounted whole (no sub_path) without
# colliding.
resource "kubernetes_secret_v1" "anthropic_api_key" {
  metadata {
    name = "home-agent-anthropic-api-key"
  }

  data = {
    "anthropic_api_key" = var.home_agent_anthropic_api_key
  }

  type = "Opaque"
}

# Mounted into the nextcloud-tools sidecar at /etc/nextcloud-tools,
# matching NEXTCLOUD_APP_PASSWORD_FILE's own default path in
# nextcloud_tools_service.py.
resource "kubernetes_secret_v1" "nextcloud_tools_app_password" {
  metadata {
    name = "nextcloud-tools-app-password"
  }

  data = {
    "app-password" = var.nextcloud_tools_app_password
  }

  type = "Opaque"
}
