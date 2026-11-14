# Argo CD runs this app's workload from k3s-apps' argocd/; Secrets and PVCs stay here. See README, "Argo CD".

removed {
  from = kubernetes_deployment_v1.open_webui

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_service_v1.open_webui

  lifecycle {
    destroy = false
  }
}

# Restarts Argo CD's Pod when a Secret here changes; Argo CD's manifest leaves these annotations out.
resource "kubernetes_annotations" "open_webui_checksums" {
  api_version   = "apps/v1"
  kind          = "Deployment"
  field_manager = "terraform-secret-checksums"
  force         = true

  metadata {
    namespace = "apps"
    name      = "open-webui"
  }

  template_annotations = {
    "checksum/oidc-client-secret" = sha256(kubernetes_secret_v1.open_webui_oidc_client_secret.data["OAUTH_CLIENT_SECRET"])
  }
}
