# Argo CD runs this app from k3s-apps' argocd/, ESO supplies its Secrets; Terraform only forgets. See README, "Argo CD".

removed {
  from = kubernetes_deployment_v1.grafana

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_service_v1.grafana

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_config_map_v1.grafana_dashboard_provider

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_config_map_v1.grafana_dashboards

  lifecycle {
    destroy = false
  }
}

# Restarts Argo CD's Pod when a Secret here changes; Argo CD's manifest leaves these annotations out.
removed {
  from = kubernetes_annotations.grafana_checksums

  lifecycle {
    destroy = false
  }
}

# The Secrets moved to ESO (argocd/grafana/externalsecret.yaml, ADR 0032); forgotten here, never deleted.
removed {
  from = random_password.grafana_admin

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_secret_v1.grafana_admin_password

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_secret_v1.grafana_oidc_client_secret

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_secret_v1.grafana_datasources

  lifecycle {
    destroy = false
  }
}
