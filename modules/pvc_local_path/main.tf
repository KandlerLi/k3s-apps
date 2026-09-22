# Shared shape for a small, disposable, k3s-owned PVC on the local-path
# storage class -- see any callsite's own comment (e.g.
# modules/blocky/storage.tf) for why storage_class_name is explicit and
# wait_until_bound = false. Not used for the NFS-backed PVCs (deluge,
# open_webui, authelia_backup) -- those bind to a specific,
# already-existing PersistentVolume by name, a genuinely different
# shape.

variable "name" {
  description = "Kubernetes PersistentVolumeClaim name."
  type        = string
}

variable "size" {
  description = "Requested storage size (e.g. \"128Mi\")."
  type        = string
}

resource "kubernetes_persistent_volume_claim_v1" "this" {
  metadata {
    name = var.name
  }

  wait_until_bound = false

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "local-path"

    resources {
      requests = {
        storage = var.size
      }
    }
  }
}
