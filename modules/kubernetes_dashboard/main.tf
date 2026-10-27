# Read-only Kubernetes Dashboard v2.7.0, the last single-component release; RBAC lives in k3s-bootstrap.

resource "kubernetes_deployment_v1" "kubernetes_dashboard" {
  metadata {
    namespace = "apps"
    name      = "kubernetes-dashboard"
  }

  # The Dashboard panics on startup if either Secret is missing.
  depends_on = [
    kubernetes_secret_v1.kubernetes_dashboard_csrf,
    kubernetes_secret_v1.kubernetes_dashboard_key_holder,
  ]

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "kubernetes-dashboard"
      }
    }

    template {
      metadata {
        labels = {
          app = "kubernetes-dashboard"
        }
      }

      spec {
        # Pre-created in k3s-bootstrap.
        service_account_name = "kubernetes-dashboard"

        container {
          name  = "kubernetes-dashboard"
          image = "kubernetesui/dashboard:v2.7.0@sha256:2e500d29e9d5f4a086b908eb8dfe7ecac57d2ab09d65b24f588b1d449841ef93"

          args = [
            "--namespace=apps",
            "--insecure-bind-address=0.0.0.0",
            "--insecure-port=9090",
            "--enable-skip-login",
            "--metrics-provider=none",
          ]

          port {
            name           = "http"
            container_port = 9090
          }

          # A light, mostly static UI.
          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }

          # 1001:2001, the image's documented non-root default.
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            run_as_user                = 1001
            run_as_group               = 2001
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
              scheme = "HTTP"
              path   = "/"
              port   = 9090
            }
            initial_delay_seconds = 30
            period_seconds        = 30
            timeout_seconds       = 30
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

resource "kubernetes_service_v1" "kubernetes_dashboard" {
  metadata {
    namespace = "apps"
    name      = "kubernetes-dashboard-svc"
  }

  spec {
    selector = {
      app = "kubernetes-dashboard"
    }

    port {
      port        = 80
      target_port = 9090
    }
  }
}
