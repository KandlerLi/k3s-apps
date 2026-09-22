# Small PVC for Authelia's own SQLite database (TOTP registrations,
# consent state, the reset-password JWT denylist -- not sessions, those
# live in the Redis sidecar, see authelia_redis below) -- worth surviving
# an ordinary Pod restart rather than resetting every time, the same
# "genuinely disposable but worth keeping" reasoning modules/ingress's
# own acme.json PVC and modules/blocky's own Postgres PVC both used
# already, sized the same as the former (single-user state, not a
# growing log). Shape lives in modules/pvc_local_path (extracted
# 2026-09-22, ponytail-audit -- see that module's own comment).
moved {
  from = kubernetes_persistent_volume_claim_v1.authelia_data
  to   = module.authelia_data.kubernetes_persistent_volume_claim_v1.this
}

module "authelia_data" {
  source = "../pvc_local_path"

  name = "authelia-data"
  size = "128Mi"
}

# Redis sidecar's append-only file (session store). Same local-path
# reasoning as authelia_data above.
moved {
  from = kubernetes_persistent_volume_claim_v1.authelia_redis
  to   = module.authelia_redis.kubernetes_persistent_volume_claim_v1.this
}

module "authelia_redis" {
  source = "../pvc_local_path"

  name = "authelia-redis"
  size = "128Mi"
}

# NFS-backed, unlike authelia_data above -- the backup CronJob
# (cronjob.tf) writes a periodic snapshot here specifically so it
# leaves this node's own disk, landing on the homeserver's real
# filesystem instead. The matching PV (cluster-scoped, so it lives in
# bootstrap/k3s-bootstrap's own storage.tf, same split as every other
# NFS-backed PV this repo uses) points at
# /mnt/red-hdd/authelia-backup, exported to this node by
# infra/home-infra's own authelia_backup role.
resource "kubernetes_persistent_volume_claim_v1" "authelia_backup" {
  metadata {
    name = "authelia-backup"
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "local-path"
    volume_name        = "authelia-backup-pv"

    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}
