# Argo CD runs this app from k3s-apps' argocd/, ESO supplies its Secret; Terraform only forgets. See README, "Argo CD".

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
removed {
  from = kubernetes_annotations.stalwart_checksums

  lifecycle {
    destroy = false
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

# The Secret moved to ESO (argocd/stalwart/externalsecret.yaml, ADR 0032); forgotten here, never deleted.
removed {
  from = kubernetes_secret_v1.stalwart_ses_smtp

  lifecycle {
    destroy = false
  }
}
