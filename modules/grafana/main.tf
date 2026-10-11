# Prometheus stays on the homeserver, reached via 192.168.101.1. No PVC: everything is provisioned.

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

        # Provisioning is only read at startup, so checksums force a new Pod.
        annotations = {
          "checksum/oidc-client-secret" = sha256(kubernetes_secret_v1.grafana_oidc_client_secret.data["grafana.ini"])
          "checksum/datasources"        = sha256(kubernetes_secret_v1.grafana_datasources.data["datasources.yaml"])
          "checksum/admin-password"     = sha256(kubernetes_secret_v1.grafana_admin_password.data["grafana_admin_password"])
        }
      }

      spec {
        # The token mount would collide with the admin-password Secret at /run/secrets.
        automount_service_account_token = false

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
          # _FILE suffix, not a raw env var.
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
          # Hiding the form isn't enough; auth.basic must be off too.
          env {
            name  = "GF_AUTH_DISABLE_LOGIN_FORM"
            value = "true"
          }
          env {
            name  = "GF_AUTH_BASIC_ENABLED"
            value = "false"
          }

          # OIDC against Authelia: admins become Grafana Admin, everyone else Viewer.
          env {
            name  = "GF_AUTH_GENERIC_OAUTH_ENABLED"
            value = "true"
          }
          env {
            name  = "GF_AUTH_GENERIC_OAUTH_NAME"
            value = "Authelia"
          }
          env {
            name  = "GF_AUTH_GENERIC_OAUTH_CLIENT_ID"
            value = "grafana"
          }
          # No client_secret env var: see secret.tf for why it lives in grafana.ini.
          env {
            name  = "GF_AUTH_GENERIC_OAUTH_SCOPES"
            value = "openid profile email groups"
          }
          env {
            name  = "GF_AUTH_GENERIC_OAUTH_EMPTY_SCOPES"
            value = "false"
          }
          env {
            name  = "GF_AUTH_GENERIC_OAUTH_AUTH_URL"
            value = "https://auth.jkandler.de/api/oidc/authorization"
          }
          env {
            name  = "GF_AUTH_GENERIC_OAUTH_TOKEN_URL"
            value = "https://auth.jkandler.de/api/oidc/token"
          }
          env {
            name  = "GF_AUTH_GENERIC_OAUTH_API_URL"
            value = "https://auth.jkandler.de/api/oidc/userinfo"
          }
          env {
            name  = "GF_AUTH_GENERIC_OAUTH_LOGIN_ATTRIBUTE_PATH"
            value = "preferred_username"
          }
          env {
            name  = "GF_AUTH_GENERIC_OAUTH_GROUPS_ATTRIBUTE_PATH"
            value = "groups"
          }
          env {
            name  = "GF_AUTH_GENERIC_OAUTH_NAME_ATTRIBUTE_PATH"
            value = "name"
          }
          env {
            name  = "GF_AUTH_GENERIC_OAUTH_USE_PKCE"
            value = "true"
          }
          env {
            name  = "GF_AUTH_GENERIC_OAUTH_ROLE_ATTRIBUTE_PATH"
            value = "contains(groups[*], 'admins') && 'Admin' || 'Viewer'"
          }
          env {
            name  = "GF_AUTH_GENERIC_OAUTH_AUTH_STYLE"
            value = "InHeader"
          }

          # 512Mi: Grafana 13 builds an in-memory index on startup.
          resources {
            requests = {
              cpu    = "100m"
              memory = "256Mi"
            }
            limits = {
              cpu    = "300m"
              memory = "512Mi"
            }
          }

          # UID 472, GID 0: the official image's non-root default.
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
          # grafana.ini, see secret.tf.
          volume_mount {
            name       = "oidc-client-secret"
            mount_path = "/etc/grafana/grafana.ini"
            sub_path   = "grafana.ini"
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

          # Readiness and liveness on /api/health.
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
          name = "oidc-client-secret"
          secret {
            secret_name = kubernetes_secret_v1.grafana_oidc_client_secret.metadata[0].name
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
