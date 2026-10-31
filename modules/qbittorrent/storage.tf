# The NFS PVs live in k3s-bootstrap (cluster-scoped); bound here by name.

resource "kubernetes_persistent_volume_claim_v1" "deluge_downloads" {
  metadata {
    namespace = "apps"
    name      = "deluge-downloads"
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "local-path"
    volume_name        = "deluge-downloads-pv"

    resources {
      requests = {
        storage = "500Gi"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "deluge_config" {
  metadata {
    namespace = "apps"
    name      = "deluge-config"
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "local-path"
    volume_name        = "deluge-config-pv"

    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}
