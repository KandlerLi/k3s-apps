# Nextcloud AIO stays on the homeserver (192.168.101.1:11000); ExternalName needs a hostname, hence a selector-less Service plus Endpoints.
resource "kubernetes_service_v1" "nextcloud_aio_backend" {
  metadata {
    namespace = "apps"
    name      = "nextcloud-aio-backend"
  }

  spec {
    port {
      port        = 11000
      target_port = 11000
    }
  }
}

resource "kubernetes_endpoints_v1" "nextcloud_aio_backend" {
  metadata {
    namespace = "apps"
    name      = "nextcloud-aio-backend"
  }

  subset {
    address {
      ip = "192.168.101.1"
    }

    port {
      port = 11000
    }
  }
}
