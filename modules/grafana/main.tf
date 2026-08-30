# Grafana -- Phase 1 of moving home-infra's `monitoring` role into k3s
# (see infra's plan doc). Prometheus/Alertmanager/the exporters/Blocky
# all stay on the homeserver (node_exporter and cAdvisor report *this
# physical host's* own hardware/Docker daemon, blackbox_exporter and
# Blocky are LAN-facing -- none of that makes sense running anywhere
# else), reached here over the additive 192.168.101.1 listeners
# home-infra's blocky and monitoring roles now expose (see
# blocky_postgres_k3s_bind_address / monitoring_prometheus_k3s_bind_
# address).
#
# No PVC, deliberately -- everything Grafana needs (datasources,
# dashboard provider, the five dashboard JSONs) is provisioned from
# files below, the same "no click-through UI state to lose" reasoning
# home-infra's own role's README already gives, confirmed with Julian
# before applying rather than assumed. /var/lib/grafana is a plain
# emptyDir: Grafana's own sqlite (session state, not dashboards/
# datasources, which are file-provisioned and reappear on restart) is
# genuinely disposable here.
#
# CPU/memory sized off Grafana's own real docker stats on the
# homeserver (0.68% CPU idle, 169MiB/256M memory) the same way
# open_webui's module was -- Burstable requests/limits, not a copied
# Docker cpus: ceiling. Only 350m of the k3s VM's 2 vCPU budget was
# free before this module (`kubectl describe node`); 100m request
# leaves headroom for Deluge/home_agent/open_webui's own bursts.

resource "kubernetes_deployment_v1" "grafana" {
  metadata {
    name = "grafana"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "grafana"
      }
    }

    template {
      metadata {
        labels = {
          app = "grafana"
        }
      }

      spec {
        container {
          name  = "grafana"
          image = "grafana/grafana:13.1.4@sha256:9be3a3ccdb06bcbb127f888b0c4c1d151837443e478887897a63a27d7b348043"

          port {
            name           = "http"
            container_port = 3000
          }

          env {
            name  = "GF_SECURITY_ADMIN_USER"
            value = "admin"
          }
          # Same "_FILE suffix, not a raw env var" convention as
          # home-infra's own deployment.
          env {
            name  = "GF_SECURITY_ADMIN_PASSWORD__FILE"
            value = "/run/secrets/grafana_admin_password"
          }
          env {
            name  = "GF_SERVER_ROOT_URL"
            value = "https://grafana.jkandler.de/"
          }
          env {
            name  = "GF_ANALYTICS_REPORTING_ENABLED"
            value = "false"
          }
          env {
            name  = "GF_ANALYTICS_CHECK_FOR_UPDATES"
            value = "false"
          }
          env {
            name  = "GF_ANALYTICS_CHECK_FOR_PLUGIN_UPDATES"
            value = "false"
          }
          env {
            name  = "GF_USERS_ALLOW_SIGN_UP"
            value = "false"
          }

          resources {
            requests = {
              cpu    = "100m"
              memory = "192Mi"
            }
            limits = {
              cpu    = "300m"
              memory = "320Mi"
            }
          }

          # UID 472, GID 0 -- Grafana's official image's own documented
          # non-root default UID, paired with the root group the image
          # ships group-writable permissions for (same "arbitrary UID,
          # root group" shape as open_webui's 995:0, but there's no
          # host-owned directory to match here since nothing is
          # bind-mounted -- everything below is either an emptyDir or a
          # read-only ConfigMap/Secret mount).
          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 472
            run_as_group               = 0
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "datasources"
            mount_path = "/etc/grafana/provisioning/datasources"
            read_only  = true
          }
          volume_mount {
            name       = "dashboard-provider"
            mount_path = "/etc/grafana/provisioning/dashboards"
            read_only  = true
          }
          volume_mount {
            name       = "dashboards"
            mount_path = "/var/lib/grafana-dashboards"
            read_only  = true
          }
          volume_mount {
            name       = "admin-password"
            mount_path = "/run/secrets"
            read_only  = true
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/grafana"
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          # Mirrors home-infra's own Docker healthcheck (wget --spider
          # http://127.0.0.1:3000/api/health, 30s start_period) as
          # readiness/liveness probes.
          readiness_probe {
            http_get {
              path = "/api/health"
              port = 3000
            }
            initial_delay_seconds = 30
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 5
          }
          liveness_probe {
            http_get {
              path = "/api/health"
              port = 3000
            }
            initial_delay_seconds = 30
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 5
          }
        }

        volume {
          name = "datasources"
          secret {
            secret_name = kubernetes_secret_v1.grafana_datasources.metadata[0].name
          }
        }
        volume {
          name = "dashboard-provider"
          config_map {
            name = kubernetes_config_map_v1.grafana_dashboard_provider.metadata[0].name
          }
        }
        volume {
          name = "dashboards"
          config_map {
            name = kubernetes_config_map_v1.grafana_dashboards.metadata[0].name
          }
        }
        volume {
          name = "admin-password"
          secret {
            secret_name = kubernetes_secret_v1.grafana_admin_password.metadata[0].name
          }
        }
        volume {
          name = "data"
          empty_dir {}
        }
        volume {
          name = "tmp"
          empty_dir {
            medium     = "Memory"
            size_limit = "32Mi"
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "grafana" {
  metadata {
    name = "grafana-svc"
  }

  spec {
    selector = {
      app = "grafana"
    }

    port {
      port        = 80
      target_port = 3000
    }
  }
}

resource "kubernetes_ingress_v1" "grafana" {
  metadata {
    name = "grafana-ingress"
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      # Not published via shared_ingress_grafana_upstream yet -- this
      # Ingress has to exist and be verified first (real dashboards,
      # real data) before home-infra's own cutover step can point
      # traffic at it, same sequencing as every prior service.
      host = "grafana.jkandler.de"

      http {
        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = kubernetes_service_v1.grafana.metadata[0].name

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
