# Terraform equivalent of home-infra's ansible/roles/landing_page role --
# same image digest, same mount point, same links -- run against the k3s
# learning cluster instead of a Docker container on the homeserver. The
# real index.html/style.css content lives in files/ in this repo (pulled
# from the live homeserver, not fabricated), read in via file() below,
# the same way the Ansible role templates them from its own source.

resource "kubernetes_config_map_v1" "landing_page_html" {
  metadata {
    name = "landing-page-html"
  }

  data = {
    "index.html" = file("${path.module}/files/index.html")
    "style.css"  = file("${path.module}/files/style.css")
  }
}

resource "kubernetes_deployment_v1" "landing_page" {
  metadata {
    name = "landing-page"
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
        container {
          name = "landing-page"
          # Same pinned digest as ansible/roles/landing_page/defaults/main.yml
          image = "nginxinc/nginx-unprivileged:1.27-alpine@sha256:65e3e85dbaed8ba248841d9d58a899b6197106c23cb0ff1a132b7bfe0547e4c0"

          port {
            container_port = 8080
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
    name = "landing-page-svc"
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

resource "kubernetes_ingress_v1" "landing_page" {
  metadata {
    name = "landing-page-ingress"
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = "landing.k3s.local"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.landing_page.metadata[0].name

              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
