# Argo CD runs this app from k3s-apps' argocd/, ESO supplies its Secrets; Terraform only forgets. See README, "Argo CD".

removed {
  from = kubernetes_cron_job_v1.sankey_export

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_persistent_volume_claim_v1.sankey_export_state

  lifecycle {
    destroy = false
  }
}

# The Secrets moved to ESO (argocd/sankey-export/externalsecret.yaml, ADR 0032); forgotten here, never deleted.
removed {
  from = module.ghcr_pull_secret

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_secret_v1.sankey_export_app_password

  lifecycle {
    destroy = false
  }
}
