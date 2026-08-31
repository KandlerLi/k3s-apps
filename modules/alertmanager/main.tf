# Phase 2 of moving home-infra's `monitoring` role into k3s (Grafana was
# Phase 1). Alertmanager itself has no host dependency at all -- it just
# evaluates config and posts webhooks/SMTP -- so unlike node_exporter/
# cAdvisor/blackbox_exporter/Blocky, this one can move outright rather
# than needing a network exception in both directions the way Grafana's
# datasources did.
#
# The direction here is the reverse of Grafana's: Prometheus (staying on
# the homeserver) needs to reach *this*, not the other way around.
# Prometheus's own alerting.alertmanagers target list notifies every
# address in it for the same firing alert (unlike a scrape target list),
# so running the old homeserver Alertmanager and this one at the same
# time would double-fire every real notification -- home-infra's own
# monitoring_alertmanager_upstream switches cleanly to this module's
# LoadBalancer address only once this is independently verified working
# (a real synthetic alert reaching both ntfy and SES), never both at
# once.
#
# No PVC, deliberately -- confirmed with Julian first (same question
# already asked for Grafana): Alertmanager's own /alertmanager directory
# holds active silences and a notification-dedup log, not real history,
# so starting fresh is low-stakes (a handful of already-notified alerts
# might re-fire once).
#
# CPU/memory sized off Alertmanager's own real docker stats on the
# homeserver (0.77% of one core, 17.67MiB/128MiB memory -- genuinely
# idle almost all the time) -- Burstable requests/limits, not a copied
# Docker cpus: ceiling. Only 250m of the k3s VM's 2 vCPU budget was
# free before this module (`kubectl describe node`), the tightest
# headroom yet; 20m request comfortably covers real observed usage with
# room to spare.

resource "kubernetes_deployment_v1" "alertmanager" {
  metadata {
    name = "alertmanager"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "alertmanager"
      }
    }

    template {
      metadata {
        labels = {
          app = "alertmanager"
        }
      }

      spec {
        # Alertmanager doesn't talk to the Kubernetes API -- see
        # modules/grafana's own comment on this exact collision class
        # (a Secret mounted at a path under /run or /etc doesn't hit
        # it the way /run/secrets directly did there, but there's no
        # reason to auto-mount a token nothing here reads either).
        automount_service_account_token = false

        container {
          name  = "alertmanager"
          image = "prom/alertmanager:v0.34.0@sha256:690c7b525f4367aa91f73e2f91c632206d32e97c6384bdbf2fb7a861b420340d"

          port {
            name           = "http"
            container_port = 9093
          }

          args = [
            "--config.file=/etc/alertmanager/alertmanager.yml",
            "--storage.path=/alertmanager",
          ]

          resources {
            requests = {
              cpu    = "20m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "96Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            # Official image's own conventional non-root UID (nobody),
            # paired with the root group -- no host-owned directory to
            # match here since nothing is bind-mounted (no PVC).
            run_as_user               = 65534
            run_as_group              = 0
            read_only_root_filesystem = true
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/etc/alertmanager"
            read_only  = true
          }
          volume_mount {
            name       = "data"
            mount_path = "/alertmanager"
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          readiness_probe {
            http_get {
              path = "/-/ready"
              port = 9093
            }
            initial_delay_seconds = 10
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 5
          }
          liveness_probe {
            http_get {
              path = "/-/healthy"
              port = 9093
            }
            initial_delay_seconds = 10
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 5
          }
        }

        volume {
          name = "config"
          secret {
            secret_name = kubernetes_secret_v1.alertmanager_config.metadata[0].name
          }
        }
        volume {
          name = "data"
          empty_dir {}
        }
        volume {
          name = "tmp"
          empty_dir {
            medium     = "Memory"
            size_limit = "16Mi"
          }
        }
      }
    }
  }
}

# Alertmanager isn't a browser-facing app, and Prometheus needs a plain
# IP:port target rather than Host-based routing -- so this reuses
# modules/deluge's own deluge-peer-svc mechanism instead of a ClusterIP
# + Ingress: type = LoadBalancer lets k3s's bundled ServiceLB (the same
# svclb-* pods already fronting Traefik and Deluge's peer port) bind
# this directly to the node's own address, giving a stable
# 192.168.101.10:9093 -- same port number Alertmanager already uses on
# the homeserver today, so home-infra's own monitoring_alertmanager_upstream
# only ever has two literal values to compare against. No Ingress at
# all: Alertmanager has never been reachable through shared_ingress,
# and this doesn't change that.
resource "kubernetes_service_v1" "alertmanager" {
  metadata {
    name = "alertmanager-svc"
  }

  spec {
    type = "LoadBalancer"

    selector = {
      app = "alertmanager"
    }

    port {
      port        = 9093
      target_port = 9093
    }
  }
}
