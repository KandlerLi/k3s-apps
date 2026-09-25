# Nightly document_exporter into the red HDD (ADR 0023): originals,
# archive PDFs and a manifest of all metadata, restorable with
# document_importer into any later Paperless version. Incremental, and
# --delete keeps it a mirror; accidental deletions are covered by
# Paperless's own 30-day trash. 04:15 keeps clear of the other red-HDD
# jobs (Nextcloud Borg 03:00, aux_backup 03:30, authelia-backup 03:45).

resource "kubernetes_cron_job_v1" "paperless_export" {
  metadata {
    name = "paperless-export"
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
        active_deadline_seconds = 3600

        template {
          metadata {
            labels = {
              app = "paperless-export"
            }
          }

          spec {
            restart_policy                  = "Never"
            automount_service_account_token = false

            container {
              name        = "paperless-export"
              image       = local.image
              working_dir = local.src_dir
              # manage.py directly: the image's document_exporter
              # wrapper expects the s6 environment that only /init sets
              # up.
              command = ["python3", "manage.py", "document_exporter", local.export, "--delete", "--no-progress-bar"]

              dynamic "env" {
                for_each = merge(local.common_env, {
                  PAPERLESS_DBHOST   = kubernetes_service_v1.paperless.metadata[0].name
                  PAPERLESS_DATA_DIR = "/tmp/paperless-data"
                })
                content {
                  name  = env.key
                  value = env.value
                }
              }

              env_from {
                secret_ref {
                  name = kubernetes_secret_v1.paperless_env.metadata[0].name
                }
              }

              resources {
                requests = {
                  cpu    = "50m"
                  memory = "256Mi"
                }
                limits = {
                  cpu    = "1"
                  memory = "1Gi"
                }
              }

              security_context {
                allow_privilege_escalation = false
                run_as_non_root            = true
                run_as_user                = local.uid
                run_as_group               = local.gid
                capabilities {
                  drop = ["ALL"]
                }
              }

              volume_mount {
                name       = "media"
                mount_path = local.media
                read_only  = true
              }
              volume_mount {
                name       = "export"
                mount_path = local.export
              }
              volume_mount {
                name       = "tmp"
                mount_path = "/tmp"
              }
            }

            volume {
              name = "media"
              persistent_volume_claim {
                claim_name = kubernetes_persistent_volume_claim_v1.paperless_media.metadata[0].name
              }
            }
            volume {
              name = "export"
              persistent_volume_claim {
                claim_name = kubernetes_persistent_volume_claim_v1.paperless_export.metadata[0].name
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
