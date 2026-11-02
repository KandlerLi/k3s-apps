# No PVC: silences and the dedup log are fine to lose. History: history.md ("k3s learning cluster").

resource "kubernetes_deployment_v1" "alertmanager" {
  metadata {
    name      = "alertmanager"
    namespace = "monitoring"
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

        # Live reload of a changed config isn't confirmed, so a checksum forces a new Pod.
        annotations = {
          "checksum/config" = sha256(kubernetes_secret_v1.alertmanager_config.data["alertmanager.yml"])
        }
      }

      spec {
        # Doesn't talk to the Kubernetes API.
        automount_service_account_token = false

        security_context {
          # The provider otherwise sends false, which the namespace's restricted level rejects.
          run_as_non_root = true

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "alertmanager"
          image = "prom/alertmanager:v0.34.2@sha256:39d8bb3966c694a124428a3a88fbcffd40bd069129ecd47c059f8a3f17c55f3b"

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
            # The image's non-root UID (nobody) with the root group.
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

# LoadBalancer: Prometheus needs a plain IP:port (192.168.101.10:9093), not Host routing.
resource "kubernetes_service_v1" "alertmanager" {
  metadata {
    name      = "alertmanager-svc"
    namespace = "monitoring"
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
