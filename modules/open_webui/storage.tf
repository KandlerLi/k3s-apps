# The PV this PVC binds to lives in the separate k3s-bootstrap repo --
# see modules/deluge's own identical storage.tf comment for why.

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
