# home_agent's Secrets and their checksums; Argo CD runs the workload from argocd/home-agent. See README, "Argo CD".

removed {
  from = kubernetes_deployment_v1.home_agent

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_service_v1.home_agent

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_config_map_v1.nextcloud_tools_source

  lifecycle {
    destroy = false
  }
}

# Restarts Argo CD's Pod when a Secret here changes; Argo CD's manifest leaves these annotations out.
resource "kubernetes_annotations" "home_agent_checksums" {
  api_version   = "apps/v1"
  kind          = "Deployment"
  field_manager = "terraform-secret-checksums"
  force         = true

  metadata {
    namespace = "apps"
    name      = "home-agent"
  }

  template_annotations = {
    "checksum/openai-api-key"         = sha256(kubernetes_secret_v1.openai_api_key.data["openai_api_key"])
    "checksum/anthropic-api-key"      = sha256(kubernetes_secret_v1.anthropic_api_key.data["anthropic_api_key"])
    "checksum/nextcloud-app-password" = sha256(kubernetes_secret_v1.nextcloud_tools_app_password.data["app-password"])
  }
}
