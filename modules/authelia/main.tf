# Authelia, not Authentik -- needs no second stateful sidecar (SQLite is
# enough for a single-user homelab, no Postgres). A small Redis sidecar
# keeps sessions across restarts. Full cutover history (the Basic Auth
# replacement, the SQLite rollback/re-cutover): docs/home-infra-ai-context's
# current-state.md ("k3s learning cluster", Authelia SSO entry).
#
# The image declares no USER (defaults to root) -- security_context
# below runs it as 65534/nobody instead, the same non-root UID already
# proven writing into a local-path PVC with no chown step elsewhere in
# this repo.

resource "kubernetes_deployment_v1" "authelia" {
  metadata {
    name = "authelia"
  }

  spec {
    replicas = 1

    # Recreate, not the RollingUpdate default -- avoids two Pods briefly
    # mounting the same local-path-backed SQLite database at once (see
    # modules/blocky's own strategy block for the same risk).
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

        # Neither Secret live-propagates into a sub_path mount -- only a
        # Pod recreation picks up new content (see modules/ingress's own
        # identical checksum-annotation fix).
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

          # Sized for continuous forward-auth traffic from every gated
          # service's own background polling, not just page loads -- see
          # current-state.md for the OOM that motivated this.
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
          # false) -- this image crash-loops with it true, writing
          # somewhere on its own root filesystem at startup outside
          # /data, /config, or /tmp. See current-state.md.
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
# forwardAuth middleware (authelia-forward-auth in
# modules/ingress/configmap.tf) and the portal router (this module's
# outputs.tf) both reach it over this Service's
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
