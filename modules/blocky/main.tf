# Blocky and Postgres share one Pod, not two -- Blocky's own
# queryLog.target connects via 127.0.0.1, which a shared Pod network
# namespace reproduces with no config changes. Full cutover history and
# every bug found building this: docs/home-infra-ai-context's
# current-state.md ("k3s learning cluster", Blocky entry).

resource "kubernetes_deployment_v1" "blocky" {
  metadata {
    name = "blocky"
  }

  spec {
    replicas = 1

    # Recreate, not the RollingUpdate default -- avoids two Pods'
    # Postgres sidecars briefly mounting the same local-path data
    # directory at once. See current-state.md for the corruption this
    # caused.
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

        # Neither Secret live-propagates -- config.yml is a sub_path
        # mount, and blocky_postgres_credentials feeds the postgres
        # sidecar via env_from, read once at container start. Same
        # checksum-annotation fix as modules/ingress/modules/alertmanager.
        annotations = {
          "checksum/config"               = sha256(kubernetes_secret_v1.blocky_config.data["config.yml"])
          "checksum/postgres-credentials" = sha256(jsonencode(kubernetes_secret_v1.blocky_postgres_credentials.data))
        }
      }

      spec {
        # Neither container talks to the Kubernetes API.
        automount_service_account_token = false

        container {
          name  = "blocky"
          image = "ghcr.io/0xerr0r/blocky:v0.34.0@sha256:595136fb127f4c952b621113e668c09acdcf15ac054d96ee6d4c51a76c35f5fd"

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

          # Blocky's own image is FROM scratch -- no shell, so its
          # binary ships a "healthcheck" subcommand for exactly this.
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

        # Blocky's own query-log Postgres writer has no reconnect logic
        # and its `up` metric stays green through a silent logging gap
        # -- see current-state.md. A regular container, not a native
        # sidecar: it only needs Postgres reachable, not to start
        # before it.
        container {
          name  = "postgres-exporter"
          image = "quay.io/prometheuscommunity/postgres-exporter:v0.17.1@sha256:38606faa38c54787525fb0ff2fd6b41b4cfb75d455c1df294927c5f611699b17"

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

        # A native sidecar (restart_policy = "Always" on an
        # init_container -- KEP-753), not a regular container -- starts
        # before the Pod's main containers and blocks them until its
        # own readiness_probe first succeeds. See current-state.md for
        # the startup race this avoids.
        init_container {
          name  = "postgres"
          image = "postgres:17-alpine@sha256:18cfe3ef5e6815560c98237d6216d1e5119702fb0f3894c8785dd58b8bbe5d73"

          restart_policy = "Always"

          port {
            name           = "postgres"
            container_port = 5432
          }

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.blocky_postgres_credentials.metadata[0].name
            }
          }

          # 0.0.0.0, not 127.0.0.1 -- blocky-svc's own postgres port
          # DNATs to this Pod's real IP, unreachable if Postgres only
          # listens on loopback. args, not command: command would
          # bypass the image's own entrypoint (which chowns the data
          # directory and drops root before exec'ing the server). See
          # current-state.md.
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

# type = LoadBalancer -- k3s's bundled ServiceLB binds this to
# k3s-node-1's own address, giving home-infra's k3s_ingress_forward
# role a stable 192.168.101.10:53 (tcp+udp) DNAT target. postgres/http
# don't need DNAT but ride along on the same Service for one stable
# address.
resource "kubernetes_service_v1" "blocky" {
  metadata {
    name = "blocky-svc"
  }

  wait_for_load_balancer = false

  spec {
    type = "LoadBalancer"
    # Local, not the Cluster default -- Cluster masquerades the real
    # LAN client's source IP before Blocky ever sees it, defeating the
    # query log's whole purpose. Safe here since Blocky's Pod and this
    # Service's LoadBalancer IP are both pinned to the same node. See
    # current-state.md.
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
