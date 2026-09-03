# The kubernetes_persistent_volume_v1 this PVC binds to
# (open-webui-data-pv -- NFS-backed, storage_class_name = "local-path",
# reclaim_policy = "Retain") now lives in bootstrap/storage.tf, not
# here -- moved 2026-09-03, same reasoning as modules/deluge's own
# identical change: PersistentVolume is cluster-scoped and this
# module is applied by this repo's CI pipeline under a namespace-scoped
# Role that deliberately can't touch it. volume_name below references
# that PV by its stable name string rather than a Terraform attribute,
# since the two roots have separate state now.

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
