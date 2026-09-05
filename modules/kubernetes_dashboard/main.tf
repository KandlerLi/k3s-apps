# Kubernetes Dashboard -- a read-only, at-a-glance web UI for this
# cluster's own workloads/nodes/events. v2.7.0, the last single-
# component release before v7 split the project into separate
# auth/api/web microservices needing cert-manager for their own
# internal mTLS -- unnecessary complexity for a single-user, read-only
# homelab view. No metrics-scraper sidecar here either (the small
# CPU/Memory sparkline graphs on Pod/Node pages) -- a real add later if
# wanted, not part of this first cut.
#
# The ServiceAccount this Deployment runs as, and every RBAC object
# granting it anything, live in the separate k3s-bootstrap repo
# instead, applied locally with real cluster-admin credentials -- see
# that repo's own dashboard_rbac.tf for why: granting RBAC is itself
# privilege-defining, so it can't be something this CI-applied root's
# own narrowly-scoped k3s-apps-ci ServiceAccount is able to do to
# itself (that Role has no serviceaccounts/roles/clusterrolebindings
# verb at all, deliberately -- see main.tf's own k3s_apps_ci Role).
# This module only ever *references* "kubernetes-dashboard" by name in
# a Pod spec, which needs no RBAC grant over the ServiceAccount object
# itself to do.
#
# Runs in --insecure mode (plain HTTP on 9090, no self-signed TLS)
# deliberately: Traefik already terminates real TLS in front of every
# other service here, and forwarding on to Dashboard's own self-signed
# cert would mean either trusting an untrusted cert or adding extra
# Traefik config to skip verifying it, for zero real security gain
# over what Basic Auth plus the "view"-only ClusterRoleBinding already
# provide. --enable-skip-login means anyone through Traefik's Basic
# Auth lands straight in the read-only cluster view, no separate token
# to copy in -- safe specifically because the underlying ServiceAccount
# can't do anything beyond that read-only view regardless of how
# someone reaches it.

resource "kubernetes_deployment_v1" "kubernetes_dashboard" {
  metadata {
    name = "kubernetes-dashboard"
  }

  # Not inferred from a real attribute reference (nothing here reads
  # either Secret's own data) -- explicit because the Dashboard
  # container panics on startup if either is missing yet, so the
  # Secrets have to exist first, not merely eventually.
  depends_on = [
    kubernetes_secret_v1.kubernetes_dashboard_csrf,
    kubernetes_secret_v1.kubernetes_dashboard_key_holder,
  ]

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "kubernetes-dashboard"
      }
    }

    template {
      metadata {
        labels = {
          app = "kubernetes-dashboard"
        }
      }

      spec {
        # Pre-created in k3s-bootstrap -- see this module's own header
        # comment. Referencing it here by name needs no RBAC grant over
        # the ServiceAccount object itself.
        service_account_name = "kubernetes-dashboard"

        container {
          name  = "kubernetes-dashboard"
          image = "kubernetesui/dashboard:v2.7.0@sha256:2e500d29e9d5f4a086b908eb8dfe7ecac57d2ab09d65b24f588b1d449841ef93"

          args = [
            "--namespace=default",
            "--insecure-bind-address=0.0.0.0",
            "--insecure-port=9090",
            "--enable-skip-login",
            "--metrics-provider=none",
          ]

          port {
            name           = "http"
            container_port = 9090
          }

          # Genuinely light -- a read-only UI serving mostly static
          # assets plus watch requests against the API server, nothing
          # like Grafana's own indexing/query workload.
          resources {
            requests = {
              cpu    = "50m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "128Mi"
            }
          }

          # 1001:2001 -- the image's own documented non-root default
          # UID/GID (same pair the official recommended.yaml pins).
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            run_as_user                = 1001
            run_as_group               = 2001
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          liveness_probe {
            http_get {
              scheme = "HTTP"
              path   = "/"
              port   = 9090
            }
            initial_delay_seconds = 30
            period_seconds        = 30
            timeout_seconds       = 30
          }
        }

        volume {
          name = "tmp"
          empty_dir {}
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "kubernetes_dashboard" {
  metadata {
    name = "kubernetes-dashboard-svc"
  }

  spec {
    selector = {
      app = "kubernetes-dashboard"
    }

    port {
      port        = 80
      target_port = 9090
    }
  }
}
