# Blocky and Postgres in one Pod: the query log connects via 127.0.0.1.

resource "kubernetes_deployment_v1" "blocky" {
  metadata {
    namespace = "apps"
    name      = "blocky"
  }

  spec {
    replicas = 1

    # Recreate: two Postgres sidecars on one data directory corrupted it once.
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "blocky"
      }
    }

    template {
      metadata {
        labels = {
          app = "blocky"
        }

        # Neither Secret live-propagates, so checksums force a new Pod.
        annotations = {
          "checksum/config"               = sha256(kubernetes_secret_v1.blocky_config.data["config.yml"])
          "checksum/postgres-credentials" = sha256(jsonencode(kubernetes_secret_v1.blocky_postgres_credentials.data))
        }
      }

      spec {
        # Neither container talks to the Kubernetes API.
        automount_service_account_token = false

        security_context {
          # The provider otherwise sends false, which the restricted level rejects.
          run_as_non_root = true

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "blocky"
          image = "ghcr.io/0xerr0r/blocky:v0.35.0@sha256:4f165b63db0d76c96ecc47c7a8f57caeedc003a912bdce29abb0e283ce02e16b"

          port {
            name           = "dns-tcp"
            container_port = 53
            protocol       = "TCP"
          }
          port {
            name           = "dns-udp"
            container_port = 53
            protocol       = "UDP"
          }
          port {
            name           = "http"
            container_port = 4000
          }

          resources {
            requests = {
              cpu    = "20m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "256Mi"
            }
          }

          security_context {
            read_only_root_filesystem  = true
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 100
            capabilities {
              drop = ["ALL"]
              add  = ["NET_BIND_SERVICE"]
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/app/config.yml"
            sub_path   = "config.yml"
            read_only  = true
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          # The image is FROM scratch, so the binary has a healthcheck subcommand.
          readiness_probe {
            exec {
              command = ["/app/blocky", "healthcheck"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 5
          }
          liveness_probe {
            exec {
              command = ["/app/blocky", "healthcheck"]
            }
            initial_delay_seconds = 15
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 5
          }
        }

        # Blocky's log writer never reconnects; this exporter exposes the gap.
        container {
          name  = "postgres-exporter"
          image = "quay.io/prometheuscommunity/postgres-exporter:v0.20.1@sha256:ac5ec343104fae0e2d84a27bb8d69b38430a11910c5382cad85d478d2bab713e"

          port {
            name           = "metrics"
            container_port = 9187
          }

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.blocky_postgres_exporter_dsn.metadata[0].name
            }
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }

          security_context {
            read_only_root_filesystem  = true
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 65534
            capabilities {
              drop = ["ALL"]
            }
          }

          readiness_probe {
            http_get {
              path = "/metrics"
              port = 9187
            }
            initial_delay_seconds = 10
            period_seconds        = 15
            timeout_seconds       = 5
            failure_threshold     = 5
          }
          liveness_probe {
            http_get {
              path = "/metrics"
              port = 9187
            }
            initial_delay_seconds = 20
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 5
          }
        }

        # A native sidecar (KEP-753): Postgres is ready before Blocky starts.
        init_container {
          name  = "postgres"
          image = "postgres:17-alpine@sha256:3540c0362c809df084ffac0ae69fe794515f9de92692f02178bcdce0ef0302ac"

          restart_policy = "Always"

          # The alpine image's postgres user; owns the data directory already.
          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 70
            run_as_group               = 70
            capabilities {
              drop = ["ALL"]
            }
          }

          port {
            name           = "postgres"
            container_port = 5432
          }

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.blocky_postgres_credentials.metadata[0].name
            }
          }

          # 0.0.0.0, since blocky-svc's postgres port DNATs to the Pod IP; args keep the image's entrypoint.
          args = ["-c", "listen_addresses=0.0.0.0"]

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
              command = ["pg_isready", "-U", "blocky", "-d", "blocky_query_log"]
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 5
          }
          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "blocky", "-d", "blocky_query_log"]
            }
            initial_delay_seconds = 20
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 5
          }
        }

        volume {
          name = "config"
          secret {
            secret_name = kubernetes_secret_v1.blocky_config.metadata[0].name
          }
        }
        volume {
          name = "tmp"
          empty_dir {
            medium     = "Memory"
            size_limit = "16Mi"
          }
        }
        volume {
          name = "postgres-data"
          persistent_volume_claim {
            claim_name = module.blocky_postgres.name
          }
        }
      }
    }
  }
}

# LoadBalancer on k3s-node-1, the stable DNAT target for home-infra's k3s_ingress_forward.
resource "kubernetes_service_v1" "blocky" {
  metadata {
    namespace = "apps"
    name      = "blocky-svc"
  }

  wait_for_load_balancer = false

  spec {
    type = "LoadBalancer"
    # Local keeps the real client IP for the query log.
    external_traffic_policy = "Local"

    selector = {
      app = "blocky"
    }

    port {
      name        = "dns-tcp"
      protocol    = "TCP"
      port        = 53
      target_port = 53
    }
    port {
      name        = "dns-udp"
      protocol    = "UDP"
      port        = 53
      target_port = 53
    }
    port {
      name        = "http"
      port        = 4000
      target_port = 4000
    }
    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
    }
    port {
      name        = "postgres-exporter"
      port        = 9187
      target_port = 9187
    }
  }
}
