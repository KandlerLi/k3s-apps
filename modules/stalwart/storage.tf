# Mailbox data (RocksDB) and Stalwart's own generated config both live on
# this one PVC, under separate sub_paths -- see main.tf. Unlike the
# start-fresh-is-fine modules here, this is real, irreplaceable mail, so
# it must survive Pod restarts; off-node backup is a separate, later step
# (this PVC is on the k3s VM's own local-path disk, not a backed-up one).
#
# storage_class_name = "local-path" explicitly and wait_until_bound =
# false, for the same reasons modules/blocky's own storage.tf documents
# (unset class is serialized ambiguously; WaitForFirstConsumer only binds
# once a Pod references the claim).
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
