# New service, part of the parked "Ingress auth: replace Basic Auth
# with Authelia" plan (see PARKED.md and this module's own secret.tf)
# -- Authelia, not Authentik, specifically because it needs no heavy second
# stateful sidecar (SQLite is enough for a single-user homelab, no
# Postgres the way Authentik's own IdP footprint would need) on
# a node that has already hit real CPU/memory pressure before. A small
# Redis sidecar was added later, only to keep sessions across restarts. This
# first apply is additive only: it stands the Pod up and wires
# auth.jkandler.de's own portal router (modules/ingress/configmap.tf),
# but doesn't yet touch any of the five hostnames still gated by
# Traefik's own Basic Auth (shared-auth) -- that cutover is a
# deliberate, separate step once a real login + TOTP enrollment is
# confirmed working end-to-end.
#
# Single Pod, no init_container, no second stateful Deployment --
# confirmed against the image's own real config (ghcr.io/authelia/
# authelia's config blob, not assumed): ExposedPorts 9091/tcp,
# Entrypoint /app/entrypoint.sh, a built-in HEALTHCHECK CMD-SHELL
# /app/healthcheck.sh matching Blocky's own "use the image's own
# health tool" precedent. The image declares no USER (defaults to
# root) -- security_context below instead mirrors modules/ingress's
# own Traefik container's choice (run_as_user 65534/nobody, no
# NET_BIND_SERVICE needed since 9091 is unprivileged) specifically
# because that's the one other container in this repo already proven
# live writing into a local-path-backed PVC as a non-root UID with no
# chown step -- the same shape this Pod's own /data mount needs.

resource "kubernetes_deployment_v1" "authelia" {
  metadata {
    name = "authelia"
  }

  spec {
    replicas = 1

    # Recreate, not the RollingUpdate default -- same SQLite-on-
    # local-path corruption risk modules/blocky's own strategy block
    # already documents in detail (two Pods briefly mounting the same
    # underlying directory at once). Authelia's own SQLite database is
    # exactly the same shape of risk.
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "authelia"
      }
    }

    template {
      metadata {
        labels = {
          app = "authelia"
        }

        # Neither Secret is live-propagated into a sub_path mount by
        # Kubernetes -- only a Pod recreation picks up new content.
        # Same checksum-annotation fix modules/ingress's own Traefik
        # Deployment already uses, for the same reason.
        annotations = {
          "checksum/config" = sha256(kubernetes_secret_v1.authelia_config.data["configuration.yml"])
          "checksum/users"  = sha256(kubernetes_secret_v1.authelia_users.data["users_database.yml"])
        }
      }

      spec {
        automount_service_account_token = false

        container {
          name  = "authelia"
          image = "ghcr.io/authelia/authelia:4.39.22@sha256:936134132eaf01bfa2faf85055afbc1e0cc1cc5ca4547e9c06408fd0dd784646"

          port {
            name           = "http"
            container_port = 9091
          }

          # Bumped 2026-09-08, right after the five-chain cutover
          # (PARKED.md): confirmed live via `kubectl get pod -o
          # jsonpath='{.status.containerStatuses[0].lastState}'` --
          # exitCode 137, reason OOMKilled, repeatedly, within minutes
          # of the cutover applying. 256Mi was sized against the portal
          # alone (auth.jkandler.de, effectively single-request manual
          # testing); the cutover instantly multiplied real traffic --
          # every one of the five newly-gated services' own background
          # polling (Grafana's /api/live/ws and /api/login/ping,
          # Kubernetes Dashboard's refresh, etc.) now calls
          # /api/authz/forward-auth continuously, not just on a real
          # page load.
          resources {
            requests = {
              cpu    = "20m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "512Mi"
            }
          }

          # read_only_root_filesystem deliberately NOT set (defaults to
          # false) -- confirmed live, 2026-09-08: with it true, the
          # container crash-loops with only a generic "Errors occurred
          # performing startup checks" fatal and no further detail, even
          # at log.level: debug. Isolated via a throwaway debug Pod with
          # the exact same volumes: relocating both the SQLite path and
          # the users_database.yml path to already-writable locations
          # didn't help, but dropping only this one security_context
          # field (keeping run_as_non_root/run_as_user 65534/capabilities
          # drop ALL exactly as below) let it start cleanly and log
          # "Startup complete" -- so it's writing somewhere on its own
          # root filesystem at startup that isn't /data, /config, or
          # /tmp, and this minimal scratch-based image ships no
          # debugging tools (no strace, no shell utilities beyond
          # busybox) to pin down exactly where. Unlike
          # modules/ingress's own Traefik container, this image isn't
          # built for a fully read-only root.
          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 65534
            run_as_group               = 65534
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/config/configuration.yml"
            sub_path   = "configuration.yml"
            read_only  = true
          }
          volume_mount {
            name       = "users"
            mount_path = "/config/users_database.yml"
            sub_path   = "users_database.yml"
            read_only  = true
          }
          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          readiness_probe {
            exec {
              command = ["/app/healthcheck.sh"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 5
          }
          liveness_probe {
            exec {
              command = ["/app/healthcheck.sh"]
            }
            initial_delay_seconds = 15
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 5
          }
        }

        # Session store: Authelia's only way to keep sessions across a
        # restart is an external Redis (session.redis in secret.tf); its
        # SQLite database does not hold them. A sidecar rather than a
        # second Deployment -- one Pod, one lifecycle, and bound to
        # 127.0.0.1 so nothing else in the cluster can reach it.
        # Append-only persistence on its own PVC is what carries the
        # sessions over the Pod recreation (strategy Recreate above)
        # and a node reboot.
        container {
          name  = "redis"
          image = "redis:8-alpine@sha256:ba6e394f6acc2a695ef1b6944f161b9ca813711739be68319fa0db3470673f1d"

          args = [
            "--bind", "127.0.0.1",
            "--dir", "/redis-data",
            "--appendonly", "yes",
            "--save", "",
            "--maxmemory", "48mb",
            "--maxmemory-policy", "noeviction",
          ]

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "96Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 65534
            run_as_group               = 65534
            read_only_root_filesystem  = true
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "redis-data"
            mount_path = "/redis-data"
          }

          readiness_probe {
            exec {
              command = ["redis-cli", "-h", "127.0.0.1", "ping"]
            }
            initial_delay_seconds = 3
            period_seconds        = 10
            timeout_seconds       = 3
          }
        }

        volume {
          name = "config"
          secret {
            secret_name = kubernetes_secret_v1.authelia_config.metadata[0].name
          }
        }
        volume {
          name = "users"
          secret {
            secret_name = kubernetes_secret_v1.authelia_users.metadata[0].name
          }
        }
        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = module.authelia_data.name
          }
        }
        volume {
          name = "redis-data"
          persistent_volume_claim {
            claim_name = module.authelia_redis.name
          }
        }
        volume {
          name = "tmp"
          empty_dir {
            medium     = "Memory"
            size_limit = "16Mi"
          }
        }
      }
    }
  }
}

# ClusterIP, not LoadBalancer -- unlike Blocky/ingress, nothing outside
# the cluster ever needs to reach this Pod directly. Traefik's own
# forwardAuth middleware (modules/ingress/configmap.tf) and the portal
# router it's about to gain both reach it over this Service's
# in-cluster DNS name only.
resource "kubernetes_service_v1" "authelia" {
  metadata {
    name = "authelia-svc"
  }

  spec {
    selector = {
      app = "authelia"
    }

    port {
      name        = "http"
      port        = 9091
      target_port = 9091
    }
  }
}
