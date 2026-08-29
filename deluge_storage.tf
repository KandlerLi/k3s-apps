# Statically-provisioned NFS storage for Deluge -- deliberately not
# k3s's default local-path-provisioner (that would put data on the VM's
# own disk, invisible to Nextcloud on the homeserver). Points at the
# same two directories the real Deluge already uses
# (home-infra's deluge role), shared over NFS to exactly this VM by
# home-infra's nfs_server role. Both the mount and the exact write
# permissions (uid 993 / gid 986, Deluge's real service account) were
# confirmed live before writing this.
#
# storage_class_name = "" on both the PV and PVC opts them out of
# dynamic provisioning entirely -- without it, the PVC would try to
# match k3s's default StorageClass (local-path) instead of binding to
# this specific pre-existing PV. volume_name pins the PVC to this exact
# PV by name rather than relying on the default controller's best-guess
# matching, so there's no ambiguity as more PVs get added later.
#
# reclaim_policy = "Retain", not the "Delete" some defaults use --
# critical here specifically because this PV points at real,
# already-existing data through NFS, not disposable storage this
# cluster owns the lifecycle of. Deleting the PVC must never be able to
# touch the underlying files.
#
# The "storage" capacity/request values are nominal, not enforced --
# NFS has no concept of a Kubernetes-visible quota the way a real block
# device does. They're set generously so nothing here ever blocks on a
# false "out of space" from Kubernetes' own bookkeeping.

resource "kubernetes_persistent_volume_v1" "deluge_downloads" {
  metadata {
    name = "deluge-downloads-pv"
  }

  spec {
    capacity = {
      storage = "500Gi"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = ""

    persistent_volume_source {
      nfs {
        server = "192.168.101.1"
        path   = "/mnt/black-hdd/downloads"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "deluge_downloads" {
  metadata {
    name = "deluge-downloads"
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = ""
    volume_name        = kubernetes_persistent_volume_v1.deluge_downloads.metadata[0].name

    resources {
      requests = {
        storage = "500Gi"
      }
    }
  }
}

resource "kubernetes_persistent_volume_v1" "deluge_config" {
  metadata {
    name = "deluge-config-pv"
  }

  spec {
    capacity = {
      storage = "1Gi"
    }
    access_modes                     = ["ReadWriteMany"]
    persistent_volume_reclaim_policy = "Retain"
    storage_class_name               = ""

    persistent_volume_source {
      nfs {
        server = "192.168.101.1"
        path   = "/mnt/black-hdd/deluge-config"
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
    storage_class_name = ""
    volume_name        = kubernetes_persistent_volume_v1.deluge_config.metadata[0].name

    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}
