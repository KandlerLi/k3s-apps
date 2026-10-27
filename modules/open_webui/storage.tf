# The PV lives in k3s-bootstrap; bound here by name.

resource "kubernetes_persistent_volume_claim_v1" "open_webui_data" {
  metadata {
    namespace = "apps"
    name      = "open-webui-data"
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
