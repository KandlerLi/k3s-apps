# The NFS PV lives in k3s-bootstrap (cluster-scoped); bound here by name.
resource "kubernetes_persistent_volume_claim_v1" "vaultwarden_backup" {
  metadata {
    name      = "vaultwarden-backup"
    namespace = "apps"
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "local-path"
    volume_name        = "vaultwarden-backup-pv"

    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}
