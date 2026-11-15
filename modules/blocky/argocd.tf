# Argo CD runs this app from k3s-apps' argocd/, ESO supplies its Secrets; Terraform only forgets. See README, "Argo CD".

removed {
  from = kubernetes_deployment_v1.blocky

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_service_v1.blocky

  lifecycle {
    destroy = false
  }
}

# Restarts Argo CD's Pod when a Secret here changes; Argo CD's manifest leaves these annotations out.
removed {
  from = kubernetes_annotations.blocky_checksums

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.blocky_postgres

  lifecycle {
    destroy = false
  }
}

# The Secrets moved to ESO (argocd/blocky/externalsecret.yaml, ADR 0032); forgotten here, never deleted.
removed {
  from = kubernetes_secret_v1.blocky_config

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_secret_v1.blocky_postgres_credentials

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_secret_v1.blocky_postgres_exporter_dsn

  lifecycle {
    destroy = false
  }
}
