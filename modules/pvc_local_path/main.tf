# Shape for a small local-path PVC; not for the NFS PVCs that bind a named PV.

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
