# Authelia: SQLite is enough for one user; a Redis sidecar keeps sessions across restarts.

resource "kubernetes_deployment_v1" "authelia" {
  metadata {
    name      = "authelia"
    namespace = "auth"
  }

  spec {
    replicas = 1

    # Recreate: two Pods must never mount the same SQLite database at once.
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

        # sub_path mounts never live-refresh, so a checksum forces a new Pod.
        annotations = {
          "checksum/config" = sha256(kubernetes_secret_v1.authelia_config.data["configuration.yml"])
          "checksum/users"  = sha256(kubernetes_secret_v1.authelia_users.data["users_database.yml"])
        }
      }

      spec {
        automount_service_account_token = false

        security_context {
          # The provider otherwise sends false, which the namespace's restricted level rejects.
          run_as_non_root = true

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "authelia"
          image = "ghcr.io/authelia/authelia:4.39.28@sha256:bd97cff4fcbf715b5ff1f9ae286afbe6033afce385302520b0368122d43a6f54"

          port {
            name           = "http"
            container_port = 9091
          }

          # Sized for continuous forward-auth traffic, not just page loads.
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

          # No read_only_root_filesystem: this image writes to its root filesystem at startup.
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

        # Sessions only survive restarts in Redis: a sidecar on 127.0.0.1, its AOF on a PVC.
        container {
          name  = "redis"
          image = "redis:8-alpine@sha256:71885d8cc6e42f2bc0aa2eb853bfc4be200b5108a46ac50e117ae1df0531fb80"

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

# ClusterIP: only Traefik's forwardAuth middleware reaches it.
resource "kubernetes_service_v1" "authelia" {
  metadata {
    name      = "authelia-svc"
    namespace = "auth"
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
