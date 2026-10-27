# Shape for a small local-path PVC; not for the NFS PVCs that bind a named PV.

variable "name" {
  description = "Kubernetes PersistentVolumeClaim name."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the claim."
  type        = string
  default     = "default"
}

variable "volume_name" {
  description = "A static PV to bind instead of dynamic provisioning."
  type        = string
  default     = null
}

variable "size" {
  description = "Requested storage size (e.g. \"128Mi\")."
  type        = string
}

resource "kubernetes_persistent_volume_claim_v1" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
  }

  wait_until_bound = false

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "local-path"
    volume_name        = var.volume_name

    resources {
      requests = {
        storage = var.size
      }
    }
  }
}
