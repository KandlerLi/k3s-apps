# Argo CD runs this app's workload from k3s-apps' argocd/; Secrets and PVCs stay here. See README, "Argo CD".

removed {
  from = kubernetes_deployment_v1.authelia

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_service_v1.authelia

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_cron_job_v1.authelia_backup

  lifecycle {
    destroy = false
  }
}

# Restarts Argo CD's Pod when a Secret here changes; Argo CD's manifest leaves these annotations out.
resource "kubernetes_annotations" "authelia_checksums" {
  api_version   = "apps/v1"
  kind          = "Deployment"
  field_manager = "terraform-secret-checksums"
  force         = true

  metadata {
    namespace = "auth"
    name      = "authelia"
  }

  template_annotations = {
    "checksum/config" = sha256(kubernetes_secret_v1.authelia_config.data["configuration.yml"])
    "checksum/users"  = sha256(kubernetes_secret_v1.authelia_users.data["users_database.yml"])
  }
}
