# Argo CD runs Authelia from k3s-apps' argocd/, ESO supplies its Secrets; Terraform only forgets. See README, "Argo CD".

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
removed {
  from = kubernetes_annotations.authelia_checksums

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.authelia_data

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.authelia_redis

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_persistent_volume_claim_v1.authelia_backup

  lifecycle {
    destroy = false
  }
}

# The Secrets moved to ESO (argocd/authelia/externalsecret.yaml, ADR 0032); forgotten here, never deleted.
removed {
  from = kubernetes_secret_v1.authelia_config

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_secret_v1.authelia_users

  lifecycle {
    destroy = false
  }
}
