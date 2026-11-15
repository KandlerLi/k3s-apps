# Argo CD runs this app from k3s-apps' argocd/, ESO supplies its config Secret; Terraform only forgets. See README, "Argo CD".

removed {
  from = kubernetes_deployment_v1.alertmanager

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_service_v1.alertmanager

  lifecycle {
    destroy = false
  }
}

# Restarts Argo CD's Pod when a Secret here changes; Argo CD's manifest leaves these annotations out.
removed {
  from = kubernetes_annotations.alertmanager_checksums

  lifecycle {
    destroy = false
  }
}

# The Secret moved to ESO (argocd/alertmanager/externalsecret.yaml, ADR 0032); forgotten here, never deleted.
removed {
  from = kubernetes_secret_v1.alertmanager_config

  lifecycle {
    destroy = false
  }
}
