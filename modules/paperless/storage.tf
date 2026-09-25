# media and export bind to the static NFS PVs in bootstrap/k3s-bootstrap
# (storage.tf) by name; the directories behind them belong to
# infra/home-infra's paperless_storage role. data (search index,
# classifier) and PostgreSQL stay node-local: Paperless advises against
# databases on network storage, and the index is rebuildable.

resource "kubernetes_persistent_volume_claim_v1" "paperless_media" {
  metadata {
    name = "paperless-media"
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
    name = "paperless-export"
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

  name = "paperless-data"
  size = "5Gi"
}

module "paperless_postgres" {
  source = "../pvc_local_path"

  name = "paperless-postgres"
  size = "2Gi"
}
