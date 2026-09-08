# Small PVC for Authelia's own SQLite database (sessions, TOTP
# registrations, the reset-password JWT denylist) -- worth surviving
# an ordinary Pod restart rather than resetting every time, the same
# "genuinely disposable but worth keeping" reasoning modules/ingress's
# own acme.json PVC and modules/blocky's own Postgres PVC both used
# already, sized the same as the former (single-user state, not a
# growing log). storage_class_name = "local-path" explicitly, and
# wait_until_bound = false -- both for the same reasons those two
# modules' own storage.tf files already document in detail.
resource "kubernetes_persistent_volume_claim_v1" "authelia_data" {
  metadata {
    name = "authelia-data"
  }

  wait_until_bound = false

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "local-path"

    resources {
      requests = {
        storage = "128Mi"
      }
    }
  }
}
