# Nextcloud AIO's own Apache is the one route that isn't a k3s Service
# at all -- it stays on the homeserver permanently (nextcloud_aio's own
# role/README explain why: it manages its own sibling containers'
# lifecycle via a direct Docker socket mount, a bad fit for a
# Kubernetes Pod). Reached at 192.168.101.1:11000, the same homeserver
# address already reachable from inside the k3s VM
# (nextcloud_aio_apache_ip_binding's own precedent in home-infra).
#
# A Service of type ExternalName won't do here -- its own
# external_name field expects a real DNS hostname, and a bare IP
# address isn't a portable, reliable target for it across CoreDNS
# implementations. The correct, standard Kubernetes pattern for a
# plain external IP:port is a Service with no selector, paired with a
# matching Endpoints object naming the real address directly -- so
# Traefik's own dynamic config can reference this Service exactly like
# every in-cluster backend, with no special-casing.
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
