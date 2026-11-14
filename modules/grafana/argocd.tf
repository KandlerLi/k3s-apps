# Argo CD runs this app's workload from k3s-apps' argocd/; Secrets and PVCs stay here. See README, "Argo CD".

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
resource "kubernetes_annotations" "grafana_checksums" {
  api_version   = "apps/v1"
  kind          = "Deployment"
  field_manager = "terraform-secret-checksums"
  force         = true

  metadata {
    namespace = "monitoring"
    name      = "grafana"
  }

  template_annotations = {
    "checksum/oidc-client-secret" = sha256(kubernetes_secret_v1.grafana_oidc_client_secret.data["grafana.ini"])
    "checksum/datasources"        = sha256(kubernetes_secret_v1.grafana_datasources.data["datasources.yaml"])
    "checksum/admin-password"     = sha256(kubernetes_secret_v1.grafana_admin_password.data["grafana_admin_password"])
  }
}
