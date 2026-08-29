# Deluge itself. Same pinned image as home-infra's deluge role,
# same PUID/PGID (993/986 -- Deluge's real service account on the
# homeserver, confirmed live to have write access through the NFS
# exports in deluge_storage.tf), same "don't drop capabilities"
# reasoning: linuxserver/deluge's s6-overlay init starts as root and
# remaps to PUID/PGID via chown/setuid, which a restrictive
# securityContext (runAsNonRoot, read-only root filesystem) would
# break -- deliberately left at Kubernetes' permissive defaults here,
# matching why the Ansible role skips read_only/cap_drop for this one
# container too.

resource "kubernetes_deployment_v1" "deluge" {
  metadata {
    name = "deluge"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "deluge"
      }
    }

    template {
      metadata {
        labels = {
          app = "deluge"
        }
        annotations = {
          # subPath-mounted files (web-conf below) don't get live-
          # refreshed by Kubernetes' normal Secret-update propagation --
          # this annotation changes whenever the rendered web.conf
          # content changes (i.e. the password variable actually
          # changes), which changes the Pod template, which forces a
          # real rollout instead of a stale mounted file silently
          # surviving a password rotation.
          "checksum/web-conf" = sha256(local.deluge_web_conf)
        }
      }

      spec {
        container {
          name  = "deluge"
          image = "linuxserver/deluge:2.2.0-ls381@sha256:33a939576f7ecfc1227db1a0cb2afce030ce983e620ec9d93c956e3700e21fe9"

          env {
            name  = "PUID"
            value = "993"
          }
          env {
            name  = "PGID"
            value = "986"
          }
          env {
            name  = "TZ"
            value = "Etc/UTC"
          }

          port {
            name           = "web"
            container_port = 8112
          }
          port {
            name           = "peer-tcp"
            container_port = 6881
            protocol       = "TCP"
          }
          port {
            name           = "peer-udp"
            container_port = 6881
            protocol       = "UDP"
          }

          resources {
            limits = {
              memory = "512Mi"
              cpu    = "1000m"
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/config"
          }
          volume_mount {
            name       = "downloads"
            mount_path = "/downloads"
          }
          # Injects just this one key from the Secret as a specific
          # file inside the config PVC's own mount, rather than the
          # whole Secret as a directory -- the same "one real file
          # among the rest of Deluge's normal state" shape the Ansible
          # role's bind-mount already has.
          volume_mount {
            name       = "web-conf"
            mount_path = "/config/web.conf"
            sub_path   = "web.conf"
          }
        }

        volume {
          name = "config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.deluge_config.metadata[0].name
          }
        }
        volume {
          name = "downloads"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.deluge_downloads.metadata[0].name
          }
        }
        volume {
          name = "web-conf"
          secret {
            secret_name = kubernetes_secret_v1.deluge_web_conf.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "deluge_web" {
  metadata {
    name = "deluge-web-svc"
  }

  spec {
    selector = {
      app = "deluge"
    }

    port {
      port        = 80
      target_port = 8112
    }
  }
}

# BitTorrent's actual peer traffic -- Ingress only understands HTTP(S),
# so this needs a different mechanism entirely: a LoadBalancer Service,
# which k3s's bundled ServiceLB (the same svclb-* pods already fronting
# Traefik) picks up and binds directly to the node's own IP on exactly
# port 6881, not a randomly-assigned NodePort in the 30000+ range.
resource "kubernetes_service_v1" "deluge_peer" {
  metadata {
    name = "deluge-peer-svc"
  }

  spec {
    type = "LoadBalancer"

    selector = {
      app = "deluge"
    }

    port {
      name        = "peer-tcp"
      protocol    = "TCP"
      port        = 6881
      target_port = 6881
    }
    port {
      name        = "peer-udp"
      protocol    = "UDP"
      port        = 6881
      target_port = 6881
    }
  }
}

# Test hostname first, same as landing_page's own migration -- proven
# privately before ever touching the real torrent.jkandler.de route in
# home-infra's shared_ingress.
resource "kubernetes_ingress_v1" "deluge" {
  metadata {
    name = "deluge-ingress"
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      host = "deluge.k3s.local"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.deluge_web.metadata[0].name

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
