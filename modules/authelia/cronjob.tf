# Closes a real gap: BACKLOG.md's "Ingress auth: Authelia SQLite
# storage lost data twice during the original cutover" entry recorded
# two real losses of this exact db.sqlite3 (sessions, TOTP
# registrations, the reset-password JWT denylist) during the original
# 2026-09-08 cutover, one costing a real TOTP registration -- root
# cause was never confirmed, and until now nothing backed this data up
# at all. Deliberately separate from that entry's own root-cause
# investigation -- this doesn't explain or prevent a recurrence, it
# just makes one survivable.
#
# authelia_data (storage.tf) is a local-path/hostPath PVC -- its real
# bytes live only inside this node's own guest filesystem, invisible
# to the homeserver directly the way Deluge's/Open WebUI's own
# NFS-backed data already is. So unlike aux_backup (home-infra,
# reads homeserver-local paths straight off disk), the backup has to
# run from inside the cluster, mounting authelia_data as a second
# reader alongside Authelia's own real Pod. Kubernetes' ReadWriteOnce
# restricts a PVC to a single *node*, not a single Pod -- two Pods on
# the same node (guaranteed here, since local-path's own PV carries a
# hard nodeAffinity) can both mount it fine.
#
# Uses the exact same SQLite online-backup-API approach
# infra/home-infra's own aux_backup role already uses for Open WebUI's
# live webui.db -- a raw file copy of a WAL-mode database that's
# actively open elsewhere isn't guaranteed to be a consistent
# snapshot, and Connection.backup() is specifically designed to
# produce one without needing exclusive access.

resource "kubernetes_cron_job_v1" "authelia_backup" {
  metadata {
    name = "authelia-backup"
  }

  spec {
    schedule                      = "45 3 * * *"
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
              app = "authelia-backup"
            }
          }

          spec {
            restart_policy                  = "Never"
            automount_service_account_token = false

            container {
              name  = "authelia-backup"
              image = "python:3.13-alpine@sha256:7415fbc3c9e4979cc717d92377ab2bc7b2b4a2af1ac03cc52b5f3f88efedaf3a"

              command = ["python3", "-c", local.authelia_backup_script]

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

              # 979:979 -- infra/home-infra's own authelia_backup role
              # hardcodes the same uid/gid as its service account's
              # expected value (asserted there, not just documented),
              # so NFS's root_squash (this account is never root)
              # writes here as an identity the homeserver side already
              # owns the export directory as.
              security_context {
                read_only_root_filesystem  = true
                allow_privilege_escalation = false
                run_as_non_root            = true
                run_as_user                = 979
                run_as_group               = 979
                capabilities {
                  drop = ["ALL"]
                }
              }

              volume_mount {
                name       = "authelia-data"
                mount_path = "/authelia-data"
                read_only  = true
              }
              volume_mount {
                name       = "authelia-backup"
                mount_path = "/backup"
              }
              volume_mount {
                name       = "tmp"
                mount_path = "/tmp"
              }
            }

            volume {
              name = "authelia-data"
              persistent_volume_claim {
                claim_name = kubernetes_persistent_volume_claim_v1.authelia_data.metadata[0].name
              }
            }
            volume {
              name = "authelia-backup"
              persistent_volume_claim {
                claim_name = kubernetes_persistent_volume_claim_v1.authelia_backup.metadata[0].name
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
  # RETENTION_DAYS matches aux_backup's own default (home-infra,
  # aux_backup_retention_days) -- no shared source of truth between
  # the two repos, kept in sync by convention rather than a variable.
  authelia_backup_script = <<-PYTHON
    import glob
    import gzip
    import os
    import shutil
    import sqlite3
    import time

    SRC = "/authelia-data/db.sqlite3"
    DEST_DIR = "/backup"
    RETENTION_DAYS = 14
    TMP_DEST = "/tmp/db.sqlite3"

    date = time.strftime("%Y%m%d-%H%M%S")

    source_conn = sqlite3.connect(f"file:{SRC}?mode=ro", uri=True)
    dest_conn = sqlite3.connect(TMP_DEST)
    with dest_conn:
        source_conn.backup(dest_conn)
    source_conn.close()
    dest_conn.close()

    out_path = os.path.join(DEST_DIR, f"authelia-db-{date}.sqlite3.gz")
    with open(TMP_DEST, "rb") as f_in, gzip.open(out_path, "wb") as f_out:
        shutil.copyfileobj(f_in, f_out)
    os.remove(TMP_DEST)

    cutoff = time.time() - RETENTION_DAYS * 86400
    for old in glob.glob(os.path.join(DEST_DIR, "authelia-db-*.sqlite3.gz")):
        if os.path.getmtime(old) < cutoff:
            os.remove(old)

    print(f"Authelia backup written: {out_path}")
    PYTHON
}
