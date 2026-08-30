# home-agent's own image is a private GHCR package (ghcr.io/kandlerli/
# home-agent) -- this is what lets the cluster actually pull it.
# Read-scoped only: this credential never needs write:packages, unlike
# the token a human uses to push (see home-infra's build-home-agent.yml,
# which uses the workflow's own short-lived GITHUB_TOKEN for that
# instead of any durable credential).
resource "kubernetes_secret_v1" "ghcr_pull" {
  metadata {
    name = "ghcr-pull-secret"
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = "KandlerLi"
          password = var.home_agent_ghcr_token
          auth     = base64encode("KandlerLi:${var.home_agent_ghcr_token}")
        }
      }
    })
  }
}

# Mounted into the home-agent container at /run/secrets, matching
# OPENAI_API_KEY_FILE's own default path in api.py -- same _FILE
# convention home-infra's own Ansible deployment already uses, rather
# than a raw env var.
resource "kubernetes_secret_v1" "openai_api_key" {
  metadata {
    name = "home-agent-openai-api-key"
  }

  data = {
    "openai_api_key" = var.home_agent_openai_api_key
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
