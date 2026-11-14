# Argo CD runs this app from k3s-apps' argocd/, ESO supplies its Secret; Terraform only forgets. See README, "Argo CD".

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
removed {
  from = kubernetes_annotations.vaultwarden_checksums

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.vaultwarden_data

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_persistent_volume_claim_v1.vaultwarden_backup

  lifecycle {
    destroy = false
  }
}

# The Secret moved to ESO (argocd/vaultwarden/externalsecret.yaml, ADR 0032); forgotten here, never deleted.
removed {
  from = kubernetes_secret_v1.vaultwarden_sso

  lifecycle {
    destroy = false
  }
}
