# Renders the budget Sankey diagram every minute and uploads it to Nextcloud. History: history.md.

resource "kubernetes_cron_job_v1" "sankey_export" {
  metadata {
    namespace = "apps"
    name      = "sankey-export"
  }

  spec {
    schedule                      = "* * * * *"
    concurrency_policy            = "Forbid"
    starting_deadline_seconds     = 60
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3

    job_template {
      metadata {}

      spec {
        # No retry: the next tick a minute later picks it up.
        backoff_limit           = 0
        active_deadline_seconds = 120

        template {
          metadata {
            labels = {
              app = "sankey-export"
            }
          }

          spec {
            restart_policy = "Never"

            # Doesn't talk to the Kubernetes API.
            automount_service_account_token = false

            image_pull_secrets {
              name = module.ghcr_pull_secret.name
            }

            # fs_group doesn't fix hostPath ownership, so an initContainer chowns it.
            init_container {
              name    = "fix-state-dir-ownership"
              image   = var.sankey_export_image
              command = ["chown", "10010:10010", "/var/lib/sankey-export"]

              security_context {
                run_as_user                = 0
                run_as_group               = 0
                run_as_non_root            = false
                read_only_root_filesystem  = true
                allow_privilege_escalation = false
                capabilities {
                  drop = ["ALL"]
                  add  = ["CHOWN"]
                }
              }

              volume_mount {
                name       = "state"
                mount_path = "/var/lib/sankey-export"
              }
            }

            container {
              name  = "sankey-export"
              image = var.sankey_export_image

              env {
                name  = "SANKEY_EXPORT_ENDPOINT_HOST"
                value = "192.168.101.1"
              }
              env {
                name  = "SANKEY_EXPORT_ENDPOINT_PORT"
                value = "11000"
              }
              env {
                name  = "SANKEY_EXPORT_HTTP_HOST"
                value = "nextcloud.jkandler.de"
              }
              env {
                name  = "SANKEY_EXPORT_USERNAME"
                value = "sankey-export"
              }
              env {
                name  = "SANKEY_EXPORT_APP_PASSWORD_FILE"
                value = "/etc/sankey-export/app-password"
              }
              # Nextcloud shares don't keep the sharer's path for the recipient.
              env {
                name  = "SANKEY_EXPORT_REMOTE_DIR"
                value = "Shared/Finanzen"
              }
              env {
                name  = "SANKEY_EXPORT_WORKBOOK_NAME"
                value = "Finanzfluss_Nextcloud.xlsx"
              }
              env {
                name  = "SANKEY_EXPORT_OUTPUT_DIR"
                value = "/var/lib/sankey-export/out"
              }
              env {
                name  = "SANKEY_EXPORT_STATE_FILE"
                value = "/var/lib/sankey-export/last-etag"
              }

              # Bursty Chromium rendering: low requests, limits like the old unit.
              resources {
                requests = {
                  memory = "128Mi"
                  cpu    = "100m"
                }
                limits = {
                  memory = "768Mi"
                  cpu    = "1000m"
                }
              }

              security_context {
                read_only_root_filesystem  = true
                allow_privilege_escalation = false
                run_as_non_root            = true
                run_as_user                = 10010
                run_as_group               = 10010
                capabilities {
                  drop = ["ALL"]
                }
              }

              volume_mount {
                name       = "app-password"
                mount_path = "/etc/sankey-export"
                read_only  = true
              }
              # Backs HOME=/tmp for choreographer's cache under read_only_root_filesystem.
              volume_mount {
                name       = "tmp"
                mount_path = "/tmp"
              }
              volume_mount {
                name       = "state"
                mount_path = "/var/lib/sankey-export"
              }
            }

            volume {
              name = "app-password"
              secret {
                secret_name = kubernetes_secret_v1.sankey_export_app_password.metadata[0].name
              }
            }
            volume {
              name = "tmp"
              empty_dir {}
            }
            volume {
              name = "state"
              persistent_volume_claim {
                claim_name = kubernetes_persistent_volume_claim_v1.sankey_export_state.metadata[0].name
              }
            }
          }
        }
      }
    }
  }
}
