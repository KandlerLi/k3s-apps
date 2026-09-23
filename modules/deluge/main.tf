# Same PUID/PGID as home-infra's deluge role (993/986, its real
# service account, write access through the NFS exports). No
# restrictive securityContext -- linuxserver/deluge's s6-overlay init
# starts as root and remaps to PUID/PGID via chown/setuid, which
# runAsNonRoot/read-only-root would break.

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
          # Forces a rollout when the rendered web.conf actually
          # changes -- see modules/ingress's own identical pattern.
          "checksum/web-conf" = sha256(local.deluge_web_conf)
        }
      }

      spec {
        # Seeds web.conf into the config PVC as the real Deluge uid,
        # not a subPath mount -- see current-state.md for the
        # root_squash/CrashLoopBackOff this replaced. Only seeds if
        # missing: a later password rotation won't take effect on its
        # own (an existing web.conf is left alone), a known gap.
        init_container {
          name    = "seed-web-conf"
          image   = "linuxserver/deluge:2.2.0-ls381@sha256:33a939576f7ecfc1227db1a0cb2afce030ce983e620ec9d93c956e3700e21fe9"
          command = ["sh", "-c", "test -f /config/web.conf || cp /secret-source/web.conf /config/web.conf"]

          security_context {
            run_as_user  = 993
            run_as_group = 986
          }

          volume_mount {
            name       = "config"
            mount_path = "/config"
          }
          volume_mount {
            name       = "web-conf-source"
            mount_path = "/secret-source"
            read_only  = true
          }
        }

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
          name = "web-conf-source"
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
# so this needs a LoadBalancer Service instead, bound to a fixed port
# rather than a randomly-assigned NodePort.
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
