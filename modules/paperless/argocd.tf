# Argo CD runs this app from k3s-apps' argocd/, ESO supplies its Secrets; Terraform only forgets. See README, "Argo CD".

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
removed {
  from = kubernetes_annotations.paperless_checksums

  lifecycle {
    destroy = false
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

# The Secrets moved to ESO (argocd/paperless/externalsecret.yaml, ADR 0032); forgotten here, never deleted.
removed {
  from = random_password.secret_key

  lifecycle {
    destroy = false
  }
}

removed {
  from = random_password.postgres

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_secret_v1.paperless_postgres

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_secret_v1.paperless_env

  lifecycle {
    destroy = false
  }
}
