# Grafana -- Phase 1 of moving home-infra's `monitoring` role into k3s
# (see infra's plan doc). Prometheus stays on the homeserver
# permanently (node_exporter/cAdvisor report *this physical host's*
# own hardware/Docker daemon, so moving Prometheus itself would
# monitor the wrong thing), reached over the additive 192.168.101.1
# listener monitoring_prometheus_k3s_bind_address exposes. Blocky
# used to be LAN-facing-only for the same reason, but moved into the
# cluster too once home-infra's own k3s_ingress_forward DNAT relay
# made that viable (see modules/blocky) -- its own Postgres datasource
# below now reaches modules/blocky's own in-cluster Service directly,
# not an additive homeserver-side listener any more.
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
        # Grafana doesn't talk to the Kubernetes API, so there's nothing
        # for the default projected serviceaccount-token volume to do
        # here -- and it collides with the admin-password Secret
        # mounted at /run/secrets below: kubelet auto-mounts the token
        # at /var/run/secrets/kubernetes.io/serviceaccount, which
        # aliases (/var/run -> /run) into a subdirectory of that same
        # already-mounted path, and can't create it there. Confirmed
        # live: "mkdirat .../run/secrets/kubernetes.io: read-only file
        # system", CrashLoopBackOff -- home_agent hit the identical
        # collision (see its own main.tf) mounting its OpenAI key the
        # same way; that comment blamed read_only_root_filesystem, but
        # this module has none set and still hit it, so the real
        # trigger is the /run/secrets mount path itself, not that flag.
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
          # Confirmed live, 2026-09-09: with Authelia's own OIDC SSO
          # working (below), native login stayed live as a deliberate
          # fallback -- but Authelia's ingress-level gate only proves
          # you reached a valid Authelia session (MFA required to get
          # one); once past it, Grafana's own native login form was a
          # second, completely independent credential that skips MFA
          # entirely. disable_login_form alone only hides the UI --
          # confirmed via Grafana's own community reports that the old
          # password still works over HTTP Basic Auth even with the
          # form hidden -- so this also disables auth.basic itself,
          # the actual protocol-level switch, closing that gap for
          # real rather than just hiding it. The GF_SECURITY_ADMIN_*
          # account above still technically exists, it just can no
          # longer log in by any means -- Authelia is now the only way
          # in.
          env {
            name  = "GF_AUTH_DISABLE_LOGIN_FORM"
            value = "true"
          }
          env {
            name  = "GF_AUTH_BASIC_ENABLED"
            value = "false"
          }

          # OIDC SSO against Authelia (modules/authelia's own
          # identity_providers.oidc), added 2026-09-08 -- now the only
          # way to log in (see above). Group->role mapping matches
          # Authelia's own documented Grafana integration guide: the
          # "admins" group (the only group that exists today, see
          # modules/authelia's own users_database.yml) becomes Grafana
          # Admin, everyone else defaults to Viewer.
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

          # memory bumped from 320Mi (confirmed live 2026-09-01:
          # OOMKilled repeatedly, exit code 137, well before the
          # Deployment's own liveness probe ever got a chance to pass
          # -- Grafana 13's unified storage layer builds an in-memory
          # bleve index for folders/dashboards/playlists/etc. on every
          # startup, and a fresh Pod was already sitting at 202Mi
          # immediately after boot before that indexing work even
          # finished). The node has plenty of headroom (83% of its own
          # memory limits allocated cluster-wide at the time this was
          # raised, nowhere near capacity).
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
          # /etc/grafana/grafana.ini, the official image's own default
          # config path (confirmed live: its own baked-in copy there is
          # a fully-commented example file, nothing active, safe to
          # replace outright) -- see secret.tf's own comment for why
          # this is a real ini file, not an env var, for this one
          # setting specifically.
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
