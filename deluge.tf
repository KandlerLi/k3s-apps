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
        # Seeds web.conf into the config PVC before Deluge's own
        # container starts. NOT a subPath volume_mount into the same
        # path (what this replaced) -- Kubernetes creates a subPath
        # mount's target file at the OCI-runtime level, running as
        # root on the *node*, and that root gets squashed by NFS's
        # root_squash (deliberately configured, see nfs_server in
        # home-infra) to an unprivileged user that can't write into
        # deluge-config (owned by deluge:deluge, mode 0750). Confirmed
        # live: the Pod never started, stuck in CrashLoopBackOff with
        # "openat2 /config/web.conf: permission denied" from runc
        # itself, before Deluge's own process ever ran.
        #
        # This container's own process runs as the real Deluge uid
        # (993/986) instead, doing a normal file write through its own
        # mount of the same PVC -- no subPath, no root-level mount
        # trick, so root_squash never enters into it. Only seeds the
        # file if it's missing, matching the Ansible role's own
        # "Deluge never writes web.conf on its own until something
        # triggers a save" reasoning; deliberately simpler than that
        # role's further logic to detect and repair a known-bad
        # default password left by an old migration bug, since nothing
        # here has that history yet. This does mean a Terraform-side
        # password rotation later won't take effect on its own (an
        # existing web.conf is left alone) -- a real, acknowledged gap
        # to solve when password rotation actually comes up, not
        # bundled into getting the first deploy working.
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
