# Argo CD runs this app's workload from k3s-apps' argocd/; Secrets and PVCs stay here. See README, "Argo CD".

removed {
  from = kubernetes_deployment_v1.vaultwarden

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_service_v1.vaultwarden

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_network_policy_v1.vaultwarden

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_cron_job_v1.vaultwarden_backup

  lifecycle {
    destroy = false
  }
}

# Restarts Argo CD's Pod when a Secret here changes; Argo CD's manifest leaves these annotations out.
resource "kubernetes_annotations" "vaultwarden_checksums" {
  api_version   = "apps/v1"
  kind          = "Deployment"
  field_manager = "terraform-secret-checksums"
  force         = true

  metadata {
    namespace = "apps"
    name      = "vaultwarden"
  }

  template_annotations = {
    "checksum/sso-client-secret" = sha256(kubernetes_secret_v1.vaultwarden_sso.data["SSO_CLIENT_SECRET"])
  }
}
