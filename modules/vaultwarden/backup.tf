# Online SQLite snapshot off the node's disk; only db.sqlite3 matters (rsa_key.pem regenerates, attachments are off).

# The NFS PV lives in k3s-bootstrap (cluster-scoped); bound here by name.
resource "kubernetes_persistent_volume_claim_v1" "vaultwarden_backup" {
  metadata {
    name      = "vaultwarden-backup"
    namespace = "apps"
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "local-path"
    volume_name        = "vaultwarden-backup-pv"

    resources {
      requests = {
        storage = "1Gi"
      }
    }
  }
}

resource "kubernetes_cron_job_v1" "vaultwarden_backup" {
  metadata {
    name      = "vaultwarden-backup"
    namespace = "apps"
  }

  spec {
    schedule                      = "15 4 * * *"
    concurrency_policy            = "Forbid"
    starting_deadline_seconds     = 300
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3

    job_template {
      metadata {}

      spec {
        backoff_limit           = 0
        active_deadline_seconds = 120

        template {
          metadata {
            labels = {
              app = "vaultwarden-backup"
            }
          }

          spec {
            restart_policy                  = "Never"
            automount_service_account_token = false

            security_context {
              # The provider otherwise sends false, which the namespace's restricted level rejects.
              run_as_non_root = true

              seccomp_profile {
                type = "RuntimeDefault"
              }
            }

            container {
              name  = "vaultwarden-backup"
              image = "python:3.15-alpine@sha256:a0f2e268f2ce8f3709611a90054ec6a8ae31f6251f5896b8648b9bb99835e30a"

              command = ["python3", "-c", local.vaultwarden_backup_script]

              resources {
                requests = {
                  memory = "32Mi"
                  cpu    = "10m"
                }
                limits = {
                  memory = "128Mi"
                  cpu    = "250m"
                }
              }

              # Must match home-infra's vaultwarden_backup account, so root_squash writes as the export's owner.
              security_context {
                read_only_root_filesystem  = true
                allow_privilege_escalation = false
                run_as_non_root            = true
                run_as_user                = 981
                run_as_group               = 976
                capabilities {
                  drop = ["ALL"]
                }
              }

              volume_mount {
                name       = "vaultwarden-data"
                mount_path = "/vaultwarden-data"
                read_only  = true
              }
              volume_mount {
                name       = "vaultwarden-backup"
                mount_path = "/backup"
              }
              volume_mount {
                name       = "tmp"
                mount_path = "/tmp"
              }
            }

            volume {
              name = "vaultwarden-data"
              persistent_volume_claim {
                claim_name = module.vaultwarden_data.name
              }
            }
            volume {
              name = "vaultwarden-backup"
              persistent_volume_claim {
                claim_name = kubernetes_persistent_volume_claim_v1.vaultwarden_backup.metadata[0].name
              }
            }
            volume {
              name = "tmp"
              empty_dir {}
            }
          }
        }
      }
    }
  }
}

locals {
  # Same shape and retention as modules/authelia's backup; integrity is checked before the copy is kept.
  vaultwarden_backup_script = <<-PYTHON
    import glob
    import gzip
    import os
    import shutil
    import sqlite3
    import time

    SRC = "/vaultwarden-data/db.sqlite3"
    DEST_DIR = "/backup"
    RETENTION_DAYS = 14
    TMP_DEST = "/tmp/db.sqlite3"

    date = time.strftime("%Y%m%d-%H%M%S")

    source_conn = sqlite3.connect(f"file:{SRC}?mode=ro", uri=True)
    dest_conn = sqlite3.connect(TMP_DEST)
    with dest_conn:
        source_conn.backup(dest_conn)
    source_conn.close()
    result = dest_conn.execute("PRAGMA integrity_check").fetchone()[0]
    dest_conn.close()
    if result != "ok":
        raise SystemExit(f"snapshot failed integrity_check: {result}")

    out_path = os.path.join(DEST_DIR, f"vaultwarden-db-{date}.sqlite3.gz")
    with open(TMP_DEST, "rb") as f_in, gzip.open(out_path, "wb") as f_out:
        shutil.copyfileobj(f_in, f_out)
    os.remove(TMP_DEST)

    cutoff = time.time() - RETENTION_DAYS * 86400
    for old in glob.glob(os.path.join(DEST_DIR, "vaultwarden-db-*.sqlite3.gz")):
        if os.path.getmtime(old) < cutoff:
            os.remove(old)

    print(f"Vaultwarden backup written: {out_path}")
    PYTHON
}
