# SQLite for TOTP, consent and the JWT denylist; sessions live in Redis.
moved {
  from = kubernetes_persistent_volume_claim_v1.authelia_data
  to   = module.authelia_data.kubernetes_persistent_volume_claim_v1.this
}

module "authelia_data" {
  source = "../pvc_local_path"

  name      = "authelia-data"
  namespace = "auth"
  size      = "128Mi"
}

# Redis's append-only file (the session store).
moved {
  from = kubernetes_persistent_volume_claim_v1.authelia_redis
  to   = module.authelia_redis.kubernetes_persistent_volume_claim_v1.this
}

module "authelia_redis" {
  source = "../pvc_local_path"

  name      = "authelia-redis"
  namespace = "auth"
  size      = "128Mi"
}

# NFS-backed, so the backup snapshot leaves the node's disk.
resource "kubernetes_persistent_volume_claim_v1" "authelia_backup" {
  metadata {
    name      = "authelia-backup"
    namespace = "auth"
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
