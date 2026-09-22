# No PVC, deliberately -- Alertmanager's own /alertmanager directory
# holds active silences and a notification-dedup log, not real history,
# so starting fresh is low-stakes. Full migration history (why this
# moved outright, the double-fire risk during cutover, resource sizing):
# docs/home-infra-ai-context's current-state.md ("k3s learning cluster").

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

        # alertmanager_config is mounted as a whole directory (no
        # sub_path), so kubelet does eventually sync a changed Secret
        # into it -- but whether Alertmanager itself reloads a changed
        # config.file live isn't confirmed, so this checksum forces the
        # same deterministic, immediate Pod recreation every other
        # Secret consumer here gets.
        annotations = {
          "checksum/config" = sha256(kubernetes_secret_v1.alertmanager_config.data["alertmanager.yml"])
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
# IP:port target rather than Host-based routing -- type = LoadBalancer
# lets k3s's bundled ServiceLB bind this directly to the node's own
# address (192.168.101.10:9093, matching the port Alertmanager already
# used on the homeserver).
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
