# Replaces home-infra's deleted landing_page role; content in files/ came from the live server.

resource "kubernetes_config_map_v1" "landing_page_html" {
  metadata {
    namespace = "apps"
    name      = "landing-page-html"
  }

  data = {
    "index.html" = file("${path.module}/files/index.html")
    "style.css"  = file("${path.module}/files/style.css")
  }

  binary_data = {
    "favicon-128.png" = filebase64("${path.module}/files/favicon-128.png")
  }
}

resource "kubernetes_deployment_v1" "landing_page" {
  metadata {
    namespace = "apps"
    name      = "landing-page"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "landing-page"
      }
    }

    template {
      metadata {
        labels = {
          app = "landing-page"
        }
      }

      spec {
        security_context {
          # The provider otherwise sends false, which the restricted level rejects.
          run_as_non_root = true

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name = "landing-page"
          # Same pinned digest the old role used.
          image = "nginxinc/nginx-unprivileged:1.30.6-alpine@sha256:f5116ed4606f3eb015dd4a8e28cb9b351476dc0ad4bc6e9f93b19cec130cdf03"

          port {
            container_port = 8080
          }

          # The image's own nginx user.
          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 101
            run_as_group               = 101
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "html"
            mount_path = "/usr/share/nginx/html"
            read_only  = true
          }
        }

        volume {
          name = "html"

          config_map {
            name = kubernetes_config_map_v1.landing_page_html.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "landing_page" {
  metadata {
    namespace = "apps"
    name      = "landing-page-svc"
  }

  spec {
    selector = {
      app = "landing-page"
    }

    port {
      port        = 80
      target_port = 8080
    }
  }
}
