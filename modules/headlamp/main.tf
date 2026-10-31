# Headlamp, read-only cluster UI; RBAC lives in k3s-bootstrap.

resource "kubernetes_deployment_v1" "headlamp" {
  metadata {
    namespace = "apps"
    name      = "headlamp"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "headlamp"
      }
    }

    template {
      metadata {
        labels = {
          app = "headlamp"
        }
      }

      spec {
        # Pre-created in k3s-bootstrap.
        service_account_name = "headlamp"

        security_context {
          # The provider otherwise sends false, which the restricted level rejects.
          run_as_non_root = true

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "headlamp"
          image = "ghcr.io/headlamp-k8s/headlamp:v0.46.0@sha256:8a0ef97527544baa2b35825940ddf4db6e2d09c30cd5aa31fd269ff604cc8b75"

          # Authelia gates the route, so every visitor acts as the read-only ServiceAccount, without a token prompt.
          args = [
            "-in-cluster",
            "-unsafe-use-service-account-token",
          ]

          port {
            name           = "http"
            container_port = 4466
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }

          # 100:101, the image's headlamp user.
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            run_as_user                = 100
            run_as_group               = 101
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          liveness_probe {
            http_get {
              path = "/"
              port = 4466
            }
            period_seconds = 30
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

resource "kubernetes_service_v1" "headlamp" {
  metadata {
    namespace = "apps"
    name      = "headlamp"
  }

  spec {
    selector = {
      app = "headlamp"
    }

    port {
      port        = 80
      target_port = 4466
    }
  }
}
