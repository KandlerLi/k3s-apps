# Bulwark's own state: user preferences (encrypted settings sync) and its
# admin config/state, all under /app/data (see main.tf). The mail itself
# lives in Stalwart, not here -- losing this only resets webmail
# preferences.
#
# storage_class_name = "local-path" explicitly and wait_until_bound =
# false, for the same reasons modules/blocky's own storage.tf documents.
resource "kubernetes_persistent_volume_claim_v1" "bulwark" {
  metadata {
    name = "bulwark"
  }

  wait_until_bound = false

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "local-path"

    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}
