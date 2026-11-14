# Argo CD runs this app's workload from k3s-apps' argocd/; Secrets and PVCs stay here. See README, "Argo CD".

removed {
  from = kubernetes_deployment_v1.alertmanager

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_service_v1.alertmanager

  lifecycle {
    destroy = false
  }
}

# Restarts Argo CD's Pod when a Secret here changes; Argo CD's manifest leaves these annotations out.
resource "kubernetes_annotations" "alertmanager_checksums" {
  api_version   = "apps/v1"
  kind          = "Deployment"
  field_manager = "terraform-secret-checksums"
  force         = true

  metadata {
    namespace = "monitoring"
    name      = "alertmanager"
  }

  template_annotations = {
    "checksum/config" = sha256(kubernetes_secret_v1.alertmanager_config.data["alertmanager.yml"])
  }
}
