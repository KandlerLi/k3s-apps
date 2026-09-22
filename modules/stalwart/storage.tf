# Mailbox data (RocksDB) and Stalwart's own generated config both live
# on this one PVC, under separate sub_paths -- see main.tf. Real,
# irreplaceable mail, so it must survive Pod restarts; off-node backup
# is a separate, not-yet-done step (see current-state.md's "Mail
# server" known gaps). wait_until_bound = false -- see
# modules/blocky's own storage.tf comment for why.
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
