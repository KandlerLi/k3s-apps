# Statically-provisioned NFS storage for Deluge -- deliberately not
# k3s's default local-path-provisioner (that would put data on the VM's
# own disk, invisible to Nextcloud on the homeserver). Points at the
# same two directories the real Deluge already uses
# (home-infra's deluge role), shared over NFS to exactly this VM by
# home-infra's nfs_server role. Both the mount and the exact write
# permissions (uid 993 / gid 986, Deluge's real service account) were
# confirmed live before writing this.
#
# storage_class_name = "local-path" on both the PV and PVC -- NOT the
# empty string "" the comment here originally said, and not actually
# using k3s's local-path-provisioner despite the name. Found live: an
# explicit "" gets serialized identically to "not set at all" by this
# provider (a long-standing, widely-reported terraform-provider-
# kubernetes quirk), so k3s's DefaultStorageClass admission controller
# silently injected "local-path" into the PVC regardless of what was
# written here. That mismatched the PV's real (correctly empty)
# storage class, so they could never bind -- both PVCs sat Pending
# forever, and Terraform itself crashed trying to write that stuck
# state to disk. Matching the class name the admission controller
# injects anyway, on both sides, is the actual working fix: with
# volume_name also pointing at this specific PV and everything else
# (capacity, access mode) already satisfied, Kubernetes' own built-in
# PV controller binds them directly on the next reconcile -- the real
# local-path-provisioner is never invoked, since a suitable Available
# PV already exists and static binding always wins over dynamic
# provisioning.
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
    storage_class_name               = "local-path"

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
    storage_class_name = "local-path"
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
    storage_class_name               = "local-path"

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
    storage_class_name = "local-path"
    volume_name        = kubernetes_persistent_volume_v1.deluge_config.metadata[0].name

    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}
