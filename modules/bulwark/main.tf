# The Secrets moved to ESO (argocd/bulwark/externalsecret.yaml, ADR 0032); forgotten here, never deleted.

removed {
  from = random_id.session

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_secret_v1.bulwark_session

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_secret_v1.bulwark_oidc

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_annotations.bulwark_checksums

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_deployment_v1.bulwark

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_service_v1.bulwark

  lifecycle {
    destroy = false
  }
}
