# media and export bind to k3s-bootstrap's NFS PVs; data and PostgreSQL stay node-local.

resource "kubernetes_persistent_volume_claim_v1" "paperless_media" {
  metadata {
    namespace = "apps"
    name      = "paperless-media"
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "local-path"
    volume_name        = "paperless-media-pv"

    resources {
      requests = {
        storage = "100Gi"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "paperless_export" {
  metadata {
    namespace = "apps"
    name      = "paperless-export"
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "local-path"
    volume_name        = "paperless-export-pv"

    resources {
      requests = {
        storage = "100Gi"
      }
    }
  }
}

module "paperless_data" {
  source = "../pvc_local_path"

  name        = "paperless-data"
  namespace   = "apps"
  volume_name = "paperless-data-pv"
  size        = "5Gi"
}

module "paperless_postgres" {
  source = "../pvc_local_path"

  name        = "paperless-postgres"
  namespace   = "apps"
  volume_name = "paperless-postgres-pv"
  size        = "2Gi"
}
