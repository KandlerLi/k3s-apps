# Read-only pull credential for the private home-agent image.
moved {
  from = kubernetes_secret_v1.ghcr_pull
  to   = module.ghcr_pull_secret.kubernetes_secret_v1.this
}

module "ghcr_pull_secret" {
  source = "../ghcr_pull_secret"

  name      = "ghcr-pull-secret"
  namespace = "apps"
  token     = var.home_agent_ghcr_token
}

# Mounted at OPENAI_API_KEY_FILE's default path.
resource "kubernetes_secret_v1" "openai_api_key" {
  metadata {
    namespace = "apps"
    name      = "home-agent-openai-api-key"
  }

  data = {
    "openai_api_key" = var.home_agent_openai_api_key
  }

  type = "Opaque"
}

# Mounted at ANTHROPIC_API_KEY_FILE's default path.
resource "kubernetes_secret_v1" "anthropic_api_key" {
  metadata {
    namespace = "apps"
    name      = "home-agent-anthropic-api-key"
  }

  data = {
    "anthropic_api_key" = var.home_agent_anthropic_api_key
  }

  type = "Opaque"
}

# Mounted at NEXTCLOUD_APP_PASSWORD_FILE's default path.
resource "kubernetes_secret_v1" "nextcloud_tools_app_password" {
  metadata {
    namespace = "apps"
    name      = "nextcloud-tools-app-password"
  }

  data = {
    "app-password" = var.nextcloud_tools_app_password
  }

  type = "Opaque"
}
