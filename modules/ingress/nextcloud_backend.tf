# Nextcloud AIO's own Apache isn't a k3s Service -- it stays on the
# homeserver (192.168.101.1:11000, reachable from inside the k3s VM).
# ExternalName needs a real DNS hostname, not a bare IP, so this uses a
# selector-less Service + matching Endpoints instead, letting Traefik
# reference it exactly like any in-cluster backend.
resource "kubernetes_service_v1" "nextcloud_aio_backend" {
  metadata {
    name = "nextcloud-aio-backend"
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
    name = "nextcloud-aio-backend"
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
