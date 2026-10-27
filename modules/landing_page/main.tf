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
        container {
          name = "landing-page"
          # Same pinned digest the old role used.
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
