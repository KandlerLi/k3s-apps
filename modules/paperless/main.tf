# Paperless-ngx (ADR 0023): the personal document archive at
# docs.jkandler.de. One Pod with PostgreSQL and Redis as native sidecars
# (same pattern as modules/blocky), so the app reaches both on
# 127.0.0.1. Runs rootless as 983:978, the paperless account
# infra/home-infra's paperless_storage role pins, so NFS root_squash
# writes land as the owner of the media directory.

locals {
  image    = "ghcr.io/paperless-ngx/paperless-ngx:3.2.1@sha256:5fa76604a81df6945086e0837b14b56543d137e8ce4f311cc5d9ebe907e74e79"
  uid      = 983
  gid      = 978
  src_dir  = "/usr/src/paperless/src"
  data_dir = "/usr/src/paperless/data"
  media    = "/usr/src/paperless/media"
  export   = "/usr/src/paperless/export"

  # Shared by the app and the export CronJob.
  common_env = {
    PAPERLESS_URL       = "https://docs.jkandler.de"
    PAPERLESS_DBENGINE  = "postgresql"
    PAPERLESS_DBUSER    = "paperless"
    PAPERLESS_DBNAME    = "paperless"
    PAPERLESS_TIME_ZONE = "Europe/Berlin"
  }
}

resource "kubernetes_deployment_v1" "paperless" {
  metadata {
    name = "paperless"
  }

  spec {
    replicas = 1

    # RWO local-path volumes: stop the old Pod before starting the new.
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "paperless"
      }
    }

    template {
      metadata {
        labels = {
          app = "paperless"
        }

        annotations = {
          "checksum/env"      = sha256(jsonencode(kubernetes_secret_v1.paperless_env.data))
          "checksum/postgres" = sha256(jsonencode(kubernetes_secret_v1.paperless_postgres.data))
        }
      }

      spec {
        automount_service_account_token = false

        # Listens on 0.0.0.0 so the export CronJob can reach it through
        # paperless-svc. args, not command: the image's entrypoint
        # chowns the data directory and drops root.
        init_container {
          name           = "postgres"
          image          = "postgres:17-alpine@sha256:18cfe3ef5e6815560c98237d6216d1e5119702fb0f3894c8785dd58b8bbe5d73"
          restart_policy = "Always"
          args           = ["-c", "listen_addresses=0.0.0.0"]

          port {
            name           = "postgres"
            container_port = 5432
          }

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.paperless_postgres.metadata[0].name
            }
          }

          resources {
            requests = {
              cpu    = "20m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }

          volume_mount {
            name       = "postgres-data"
            mount_path = "/var/lib/postgresql/data"
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "paperless", "-d", "paperless"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 5
          }
          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "paperless", "-d", "paperless"]
            }
            initial_delay_seconds = 20
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 5
          }
        }

        # Task broker only; queued tasks don't survive a Pod restart,
        # which is acceptable for a single user.
        init_container {
          name           = "redis"
          image          = "redis:8-alpine@sha256:ba6e394f6acc2a695ef1b6944f161b9ca813711739be68319fa0db3470673f1d"
          restart_policy = "Always"
          args           = ["--bind", "127.0.0.1", "--save", "", "--appendonly", "no"]

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
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

          readiness_probe {
            exec {
              command = ["redis-cli", "-h", "127.0.0.1", "ping"]
            }
            initial_delay_seconds = 3
            period_seconds        = 10
            timeout_seconds       = 3
          }
        }

        container {
          name  = "paperless"
          image = local.image

          port {
            name           = "http"
            container_port = 8000
          }

          dynamic "env" {
            for_each = merge(local.common_env, {
              PAPERLESS_DBHOST = "127.0.0.1"
              PAPERLESS_REDIS  = "redis://127.0.0.1:6379"

              PAPERLESS_OCR_LANGUAGE = "deu+eng"

              # Separator sheets for scanner batches (ADR 0023).
              PAPERLESS_CONSUMER_ENABLE_BARCODES = "true"

              # SSO only in the web UI; the "admins" group in Authelia
              # makes the account a Paperless superuser on each login.
              PAPERLESS_APPS                                = "allauth.socialaccount.providers.openid_connect"
              PAPERLESS_DISABLE_REGULAR_LOGIN               = "true"
              PAPERLESS_REDIRECT_LOGIN_TO_SSO               = "true"
              PAPERLESS_SOCIAL_AUTO_SIGNUP                  = "true"
              PAPERLESS_SOCIAL_ACCOUNT_SYNC_GROUPS          = "true"
              PAPERLESS_SOCIAL_ACCOUNT_SYNC_SUPERUSER_GROUP = "admins"

              # Keep memory predictable on a small node.
              PAPERLESS_WEBSERVER_WORKERS  = "1"
              PAPERLESS_TASK_WORKERS       = "1"
              PAPERLESS_THREADS_PER_WORKER = "1"
            })
            content {
              name  = env.key
              value = env.value
            }
          }

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.paperless_env.metadata[0].name
            }
          }

          # Idle is about 750Mi; processing one phone scan was
          # OOM-killed at 1.5Gi. k3s-node-1 has about 2Gi free, so the
          # limit can't go much higher without risking the node.
          resources {
            requests = {
              cpu    = "100m"
              memory = "1Gi"
            }
            limits = {
              cpu    = "2"
              memory = "2560Mi"
            }
          }

          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = local.uid
            run_as_group               = local.gid
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "data"
            mount_path = local.data_dir
          }
          volume_mount {
            name       = "media"
            mount_path = local.media
          }
          # Unused (uploads go through the web UI/API), but Paperless's
          # startup check refuses to run unless it is writable, and the
          # image's own directory is root-owned.
          volume_mount {
            name       = "consume"
            mount_path = "/usr/src/paperless/consume"
          }

          # First start runs all database migrations, which can take a
          # while; hence the long startup window.
          startup_probe {
            tcp_socket {
              port = 8000
            }
            period_seconds    = 10
            timeout_seconds   = 3
            failure_threshold = 60
          }
          readiness_probe {
            tcp_socket {
              port = 8000
            }
            period_seconds    = 30
            timeout_seconds   = 5
            failure_threshold = 3
          }
          liveness_probe {
            tcp_socket {
              port = 8000
            }
            period_seconds    = 30
            timeout_seconds   = 5
            failure_threshold = 5
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = module.paperless_data.name
          }
        }
        volume {
          name = "media"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.paperless_media.metadata[0].name
          }
        }
        volume {
          name = "consume"
          empty_dir {}
        }
        volume {
          name = "postgres-data"
          persistent_volume_claim {
            claim_name = module.paperless_postgres.name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "paperless" {
  metadata {
    name = "paperless-svc"
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "paperless"
    }

    port {
      name        = "http"
      port        = 80
      target_port = 8000
    }
    # For the export CronJob only.
    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
    }
  }
}
