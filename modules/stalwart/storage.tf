# Mailboxes and generated config on one PVC; backed up nightly to the red HDD by backup.tf.
resource "kubernetes_persistent_volume_claim_v1" "stalwart" {
  metadata {
    namespace = "apps"
    name      = "stalwart"
  }

  wait_until_bound = false

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "local-path"
    volume_name        = "stalwart-pv"

    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
}
