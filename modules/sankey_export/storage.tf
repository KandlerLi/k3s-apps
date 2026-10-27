# Binds k3s-bootstrap's host-path PV on k3s-node-1, so the Pod has no hostPath volume of its own (PSA baseline).
resource "kubernetes_persistent_volume_claim_v1" "sankey_export_state" {
  metadata {
    name = "sankey-export-state"
  }

  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "local-path"
    volume_name        = "sankey-export-state-pv"

    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}
