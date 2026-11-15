# Argo CD runs this app from k3s-apps' argocd/, ESO supplies its Secret; Terraform only forgets. See README, "Argo CD".

removed {
  from = kubernetes_deployment_v1.ingress

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_service_v1.ingress

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_config_map_v1.ingress_static_config

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_config_map_v1.ingress_dynamic_config

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_service_v1.nextcloud_aio_backend

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_endpoints_v1.nextcloud_aio_backend

  lifecycle {
    destroy = false
  }
}

# Restarts Argo CD's Pod when a Secret here changes; Argo CD's manifest leaves these annotations out.
removed {
  from = kubernetes_annotations.ingress_checksums

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.ingress_acme

  lifecycle {
    destroy = false
  }
}

# The Secret moved to ESO (argocd/ingress/templates/externalsecret.yaml, ADR 0032); forgotten here, never deleted.
removed {
  from = kubernetes_secret_v1.ingress_acme_dns01_credentials

  lifecycle {
    destroy = false
  }
}
