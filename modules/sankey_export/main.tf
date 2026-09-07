# Renders the Finanzfluss budget Sankey diagram and uploads it to
# Nextcloud, on the same 1-minute cadence the old home-infra systemd
# timer used. finanzfluss_export.py itself needed zero code changes for
# this move -- it was already entirely env-var-configured; only the
# ETag cache (skips re-rendering when the workbook hasn't changed) needed
# a durable mount instead of a local systemd-managed disk path, via the
# host_path volume below rather than a cluster-scoped PersistentVolume
# (which would mean touching the separate, human-only k3s-bootstrap repo
# for no real benefit on a single-node cluster).
#
# 192.168.101.1:11000 is this homeserver's own address on the k3s VM's
# isolated network -- the exact same endpoint home_agent's own
# nextcloud_tools sidecar already reaches Nextcloud AIO Apache through
# (see modules/home_agent/main.tf), must stay in lockstep with
# home-infra's nextcloud_aio_apache_ip_binding.

resource "kubernetes_cron_job_v1" "sankey_export" {
  metadata {
    name = "sankey-export"
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
        # No automatic retry -- a failed tick just gets picked up by the
        # next scheduled run a minute later, same as the old systemd
        # timer never restarting a failed oneshot on its own.
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

            # Doesn't talk to the Kubernetes API -- same reasoning as
            # home_agent's own Pod (see its main.tf's comment on the
            # identical collision this avoids with a Secret mounted at
            # /run/secrets-shaped paths).
            automount_service_account_token = false

            image_pull_secrets {
              name = kubernetes_secret_v1.ghcr_pull.metadata[0].name
            }

            # Confirmed live: "PermissionError: /var/lib/sankey-export/out"
            # -- unlike emptyDir (created world-writable by kubelet), a
            # DirectoryOrCreate hostPath is created root-owned 0755 on
            # the node's own disk. A pod-level fs_group was tried first
            # (matching the pattern that fixes this for PVC-backed
            # volumes) and confirmed live NOT to work: fsGroup-based
            # ownership management only covers volume types kubelet
            # itself provisions (emptyDir, CSI volumes that opt in via
            # fsGroupPolicy) -- hostPath is explicitly excluded, kubelet
            # never touches its ownership at all (checked directly via a
            # debug Pod: still root:root 0755 after the "fix"). An
            # initContainer running as root is the standard fix for
            # exactly this gap -- it chowns the mount once before the
            # real container starts, which needs CAP_CHOWN specifically
            # (dropping every other capability, same least-privilege
            # shape as the main container below).
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
              env {
                name  = "SANKEY_EXPORT_REMOTE_DIR"
                value = "Documents/Finanzen"
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

              # Ceiling matches the old systemd unit's own
              # MemoryMax=768M/CPUQuota=100% (rendering with a real
              # headless Chromium is the expensive part), but requests
              # stay low -- this Job bursts for a few seconds once a
              # minute, not continuously, and setting limits alone
              # would default requests to match them (Guaranteed QoS),
              # reserving a full CPU against the node's schedulable
              # capacity around the clock. Confirmed live: the k3s VM's
              # 2 vCPU budget only had ~120m of request headroom left
              # once every other module's own request was accounted
              # for -- 1000m alone failed to schedule at all ("0/2
              # nodes are available: 1 Insufficient cpu"), the exact
              # same class of bug home_agent's own main.tf already
              # documents fixing.
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
              # Backs HOME=/tmp, baked into the image -- the exact
              # choreographer/platformdirs cache-dir fix from
              # home-infra#14 ("PermissionError: .../.local/share/
              # choreographer/..."), needed here for the identical
              # reason: read_only_root_filesystem plus a non-root UID
              # with no real home directory.
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
            # A different machine and path from the homeserver's own
            # /var/lib/sankey-export (that host never runs k3s Pods) --
            # no collision risk. DirectoryOrCreate so the very first run
            # doesn't need this pre-created by hand.
            volume {
              name = "state"
              host_path {
                path = "/var/lib/k3s-sankey-export"
                type = "DirectoryOrCreate"
              }
            }
          }
        }
      }
    }
  }
}
