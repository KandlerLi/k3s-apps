# The two kubernetes_persistent_volume_v1 resources these PVCs bind to
# (deluge-downloads-pv, deluge-config-pv -- NFS-backed, storage_class_name
# = "local-path", reclaim_policy = "Retain") now live in bootstrap/
# storage.tf, not here -- moved 2026-09-03 since PersistentVolume is
# cluster-scoped and this module is applied by this repo's CI pipeline
# under a namespace-scoped Role that deliberately can't touch it (see
# bootstrap/storage.tf's own comment for the full reasoning). volume_name
# below references that PV by its stable name string rather than a
# Terraform attribute, since the two roots have separate state now --
# the same name Kubernetes itself binds by either way.
#
# storage_class_name = "local-path" here too, matching the PV -- NOT the
# empty string "" a comment here once said. See bootstrap/storage.tf's
# own comment for the full explanation of why both sides need to say
# "local-path" explicitly for them to bind.

resource "kubernetes_persistent_volume_claim_v1" "deluge_downloads" {
  metadata {
    name = "deluge-downloads"
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "local-path"
    volume_name        = "deluge-downloads-pv"

    resources {
      requests = {
        storage = "500Gi"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "deluge_config" {
  metadata {
    name = "deluge-config"
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "local-path"
    volume_name        = "deluge-config-pv"

    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}
