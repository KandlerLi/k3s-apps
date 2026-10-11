# Mailboxes and generated config on one PVC; real mail, off-node backup still to do. See history.md.
resource "kubernetes_persistent_volume_claim_v1" "stalwart" {
  metadata {
    name = "stalwart"
  }

  wait_until_bound = false

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "local-path"

    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
}
