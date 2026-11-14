# Argo CD runs this app's workload from k3s-apps' argocd/; Secrets and PVCs stay here. See README, "Argo CD".

removed {
  from = kubernetes_deployment_v1.paperless

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_service_v1.paperless

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_cron_job_v1.paperless_export

  lifecycle {
    destroy = false
  }
}

# Restarts Argo CD's Pod when a Secret here changes; Argo CD's manifest leaves these annotations out.
resource "kubernetes_annotations" "paperless_checksums" {
  api_version   = "apps/v1"
  kind          = "Deployment"
  field_manager = "terraform-secret-checksums"
  force         = true

  metadata {
    namespace = "apps"
    name      = "paperless"
  }

  template_annotations = {
    "checksum/env"      = sha256(jsonencode(kubernetes_secret_v1.paperless_env.data))
    "checksum/postgres" = sha256(jsonencode(kubernetes_secret_v1.paperless_postgres.data))
  }
}

removed {
  from = kubernetes_persistent_volume_claim_v1.paperless_media

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_persistent_volume_claim_v1.paperless_export

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.paperless_data

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.paperless_postgres

  lifecycle {
    destroy = false
  }
}
