# Statically-provisioned NFS storage for Open WebUI's own data --
# same "real, already-live data through NFS, not disposable storage
# this cluster owns" shape as Deluge's own storage.tf, and the same
# storage_class_name = "local-path" quirk-workaround (see that file's
# own comment for the full explanation: an empty "" storage class gets
# silently rewritten to "local-path" by k3s's DefaultStorageClass
# admission controller regardless of what's written here, so both the
# PV and PVC have to say "local-path" explicitly for them to bind).
#
# reclaim_policy = "Retain" for the same reason as Deluge's -- deleting
# this PVC must never be able to touch the real accounts/chat history
# underneath it.
#
# Single PV, not split like Deluge's downloads/config -- home-infra's
# own open-webui container only ever had one bind mount
# (open_webui_data_dir -> /app/backend/data), covering the sqlite
# database, WEBUI_SECRET_KEY_FILE, and the HOME subdirectory together.

resource "kubernetes_persistent_volume_v1" "open_webui_data" {
  metadata {
    name = "open-webui-data-pv"
  }

  spec {
    capacity = {
      storage = "5Gi"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = "local-path"

    persistent_volume_source {
      nfs {
        server = "192.168.101.1"
        path   = "/var/lib/open-webui"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "open_webui_data" {
  metadata {
    name = "open-webui-data"
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "local-path"
    volume_name        = kubernetes_persistent_volume_v1.open_webui_data.metadata[0].name

    resources {
      requests = {
        storage = "5Gi"
      }
    }
  }
}
