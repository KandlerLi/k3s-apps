# The two kubernetes_persistent_volume_v1 resources these PVCs bind to
# (deluge-downloads-pv, deluge-config-pv -- NFS-backed, storage_class_name
# = "local-path", reclaim_policy = "Retain") live in the separate
# k3s-bootstrap repo's own storage.tf, not here -- moved 2026-09-03
# (originally to a bootstrap/ subdirectory of this same repo, later
# extracted into that standalone repo) since PersistentVolume is
# cluster-scoped and this module is applied by this repo's CI pipeline
# under a namespace-scoped Role that deliberately can't touch it (see
# that repo's own storage.tf comment for the full reasoning). volume_name
# below references that PV by its stable name string rather than a
# Terraform attribute, since the two roots (now two separate repos)
# have separate state -- the same name Kubernetes itself binds by
# either way.
#
# storage_class_name = "local-path" here too, matching the PV -- NOT the
# empty string "" a comment here once said. See k3s-bootstrap's own
# storage.tf comment for the full explanation of why both sides need to
# say "local-path" explicitly for them to bind.

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
