# Shared shape for a small, disposable, k3s-owned PVC on the local-path
# storage class -- extracted 2026-09-22 (ponytail-audit) after
# authelia_data/authelia_redis/blocky_postgres/bulwark/ingress_acme
# turned out to be byte-identical except for the PVC's own name and
# requested size, each with its own callsite comment explaining why
# that resource in particular is worth persisting.
#
# storage_class_name = "local-path" explicitly (not left unset), and
# wait_until_bound = false -- see any one of those callsites' own
# comments (e.g. modules/blocky/storage.tf) for why both matter:
# leaving storage_class_name unset gets serialized identically to
# "local-path" by this provider anyway but confuses k3s's own
# DefaultStorageClass admission controller, and local-path's own
# WaitForFirstConsumer binding mode means Terraform would otherwise
# hang forever waiting for a PVC to bind before the Pod that would
# reference it exists yet.
#
# Not used for the NFS-backed PVCs (deluge, open_webui, authelia_backup)
# -- those bind to a specific, already-existing PersistentVolume by
# name (volume_name, access_modes = ReadWriteMany), a genuinely
# different shape.

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
