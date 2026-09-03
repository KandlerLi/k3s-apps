# The kubernetes_persistent_volume_v1 this PVC binds to
# (open-webui-data-pv -- NFS-backed, storage_class_name = "local-path",
# reclaim_policy = "Retain") lives in the separate k3s-bootstrap repo's
# own storage.tf, not here -- moved 2026-09-03 (originally to a
# bootstrap/ subdirectory of this same repo, later extracted into that
# standalone repo), same reasoning as modules/deluge's own identical
# change: PersistentVolume is cluster-scoped and this module is applied
# by this repo's CI pipeline under a namespace-scoped Role that
# deliberately can't touch it. volume_name below references that PV by
# its stable name string rather than a Terraform attribute, since the
# two roots (now two separate repos) have separate state.

resource "kubernetes_persistent_volume_claim_v1" "open_webui_data" {
  metadata {
    name = "open-webui-data"
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "local-path"
    volume_name        = "open-webui-data-pv"

    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
}
