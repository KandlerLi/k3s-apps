# The two kubernetes_persistent_volume_v1 resources these PVCs bind to
# (NFS-backed, reclaim_policy = "Retain") live in the separate
# k3s-bootstrap repo -- PersistentVolume is cluster-scoped, and this
# repo's own CI Role deliberately can't touch it. volume_name
# references the PV by its stable name string, since the two repos
# have separate state.

resource "kubernetes_persistent_volume_claim_v1" "deluge_downloads" {
  metadata {
    name = "deluge-downloads"
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
    name = "deluge-config"
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
