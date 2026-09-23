# Prometheus stays on the homeserver permanently (node_exporter/
# cAdvisor report this physical host's own hardware) -- Grafana reaches
# it over the additive 192.168.101.1 listener. No PVC, deliberately --
# everything Grafana needs is provisioned from files below;
# /var/lib/grafana is a plain emptyDir, genuinely disposable. Full
# cutover history and bugs found: docs/home-infra-ai-context's
# current-state.md ("k3s learning cluster").

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

        # Grafana's own provisioning system only reads these once at
        # startup -- same checksum-annotation fix as modules/ingress.
        annotations = {
          "checksum/oidc-client-secret" = sha256(kubernetes_secret_v1.grafana_oidc_client_secret.data["grafana.ini"])
          "checksum/datasources"        = sha256(kubernetes_secret_v1.grafana_datasources.data["datasources.yaml"])
          "checksum/admin-password"     = sha256(kubernetes_secret_v1.grafana_admin_password.data["grafana_admin_password"])
        }
      }

      spec {
        # Collides with the admin-password Secret at /run/secrets
        # otherwise -- kubelet's own serviceaccount-token auto-mount
        # aliases into the same path. See current-state.md.
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
          # disable_login_form alone only hides the UI -- the old
          # password still works over HTTP Basic Auth with the form
          # hidden, so auth.basic is disabled too, the actual
          # protocol-level switch. See current-state.md.
          env {
            name  = "GF_AUTH_DISABLE_LOGIN_FORM"
            value = "true"
          }
          env {
            name  = "GF_AUTH_BASIC_ENABLED"
            value = "false"
          }

          # OIDC SSO against Authelia -- the "admins" group becomes
          # Grafana Admin, everyone else defaults to Viewer.
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
          # client_secret deliberately NOT set here -- see the mounted
          # grafana.ini (secret.tf's own comment) for why
          # GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET__FILE doesn't actually
          # work for this specific setting.
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

          # 512Mi limit -- Grafana 13's unified storage layer builds an
          # in-memory bleve index on every startup; see current-state.md
          # for the OOM this fixed.
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

          # UID 472, GID 0 -- Grafana's official image's own documented
          # non-root default, paired with the root group it ships
          # group-writable permissions for.
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
          # /etc/grafana/grafana.ini -- see secret.tf's own comment for
          # why this one setting needs a real ini file, not an env var.
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
