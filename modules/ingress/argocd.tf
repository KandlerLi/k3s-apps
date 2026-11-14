# Argo CD runs this app's workload from k3s-apps' argocd/; Secrets and PVCs stay here. See README, "Argo CD".

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
resource "kubernetes_annotations" "ingress_checksums" {
  api_version   = "apps/v1"
  kind          = "Deployment"
  field_manager = "terraform-secret-checksums"
  force         = true

  metadata {
    namespace = "apps"
    name      = "ingress"
  }

  template_annotations = {
    "checksum/acme-dns01-credentials" = sha256(jsonencode(kubernetes_secret_v1.ingress_acme_dns01_credentials.data))
  }
}
