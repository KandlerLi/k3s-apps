# Argo CD runs this app's workload from k3s-apps' argocd/; Secrets and PVCs stay here. See README, "Argo CD".

removed {
  from = kubernetes_deployment_v1.stalwart

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_service_v1.stalwart_smtp

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_service_v1.stalwart_internal

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_cron_job_v1.stalwart_backup

  lifecycle {
    destroy = false
  }
}

# Restarts Argo CD's Pod when a Secret here changes; Argo CD's manifest leaves these annotations out.
resource "kubernetes_annotations" "stalwart_checksums" {
  api_version   = "apps/v1"
  kind          = "Deployment"
  field_manager = "terraform-secret-checksums"
  force         = true

  metadata {
    namespace = "apps"
    name      = "stalwart"
  }

  template_annotations = {
    "checksum/ses-smtp" = sha256(jsonencode(kubernetes_secret_v1.stalwart_ses_smtp.data))
  }
}

removed {
  from = kubernetes_persistent_volume_claim_v1.stalwart

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_persistent_volume_claim_v1.stalwart_backup

  lifecycle {
    destroy = false
  }
}
