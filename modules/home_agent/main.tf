# Argo CD runs home_agent from argocd/home-agent, ESO supplies its Secrets; Terraform only forgets. See README, "Argo CD".

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
removed {
  from = kubernetes_annotations.home_agent_checksums

  lifecycle {
    destroy = false
  }
}

# The Secrets moved to ESO (argocd/home-agent/externalsecret.yaml, ADR 0032); forgotten here, never deleted.
removed {
  from = module.ghcr_pull_secret

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_secret_v1.openai_api_key

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_secret_v1.anthropic_api_key

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_secret_v1.nextcloud_tools_app_password

  lifecycle {
    destroy = false
  }
}
