# The backup CronJob's NFS destination; home-infra's stalwart_backup role owns it. The job: argocd/stalwart.
resource "kubernetes_persistent_volume_claim_v1" "stalwart_backup" {
  metadata {
    name      = "stalwart-backup"
    namespace = "apps"
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "local-path"
    volume_name        = "stalwart-backup-pv"

    resources {
      requests = {
        storage = "20Gi"
      }
    }
  }
}
