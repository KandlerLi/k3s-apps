# Stalwart mail server. The web admin stays cluster-internal on
# stalwart-internal:8080 (behind Traefik/Authelia at
# stalwart.jkandler.de, or `kubectl port-forward`). The plaintext
# 143/587 are not exposed anywhere. STALWART_RECOVERY_ADMIN is
# deliberately not wired yet -- needs a new Secrets Manager entry
# first, a separate change. See docs/home-infra-ai-context's
# current-state.md ("Mail server") for the fuller picture.

# Outbound mail relay credential, exposed to Stalwart as environment
# variables rather than typed into its own admin UI (its "Secret read
# from environment variable" option under MTA -> Outbound -> Routes) --
# the same SES SMTP credential aws/ses-relay's IAM policy already scopes
# to the whole jkandler.de domain, reused here rather than typed once
# into Stalwart's own database with no rotation path. The route and
# outbound strategy that use it are in modules/stalwart_config.
resource "kubernetes_secret_v1" "stalwart_ses_smtp" {
  metadata {
    name = "stalwart-ses-smtp"
  }

  data = {
    SES_SMTP_USERNAME = var.stalwart_ses_smtp_username
    SES_SMTP_PASSWORD = var.stalwart_ses_smtp_password
  }

  type = "Opaque"
}

resource "kubernetes_deployment_v1" "stalwart" {
  metadata {
    name = "stalwart"
  }

  spec {
    replicas = 1

    # One RWO local-path volume: a rolling update would try to run two
    # Pods against it. Recreate stops the old Pod first.
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "stalwart"
      }
    }

    template {
      metadata {
        labels = {
          app = "stalwart"
        }

        annotations = {
          "checksum/ses-smtp" = sha256(jsonencode(kubernetes_secret_v1.stalwart_ses_smtp.data))
        }
      }

      spec {
        automount_service_account_token = false

        # Volume ownership for the image's own unprivileged user (UID
        # 2000, `stalwart`).
        security_context {
          fs_group = 2000
        }

        container {
          name  = "stalwart"
          image = "stalwartlabs/stalwart:v0.16.22@sha256:388dcb75a70727c5b551249a6d34b1f1321294852489e4fa3a4e6be698b7c4f0"

          # Published base URL behind Traefik (modules/ingress'
          # `stalwart` routers), so redirects and JMAP session URLs use
          # the public name instead of the internal Service address.
          # mail.jkandler.de is the webmail (modules/bulwark) now.
          env {
            name  = "STALWART_PUBLIC_URL"
            value = "https://stalwart.jkandler.de"
          }
          env {
            name = "SES_SMTP_USERNAME"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.stalwart_ses_smtp.metadata[0].name
                key  = "SES_SMTP_USERNAME"
              }
            }
          }
          env {
            name = "SES_SMTP_PASSWORD"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.stalwart_ses_smtp.metadata[0].name
                key  = "SES_SMTP_PASSWORD"
              }
            }
          }

          port {
            name           = "smtp"
            container_port = 25
          }
          port {
            name           = "imaps"
            container_port = 993
          }
          port {
            name           = "submissions"
            container_port = 465
          }
          port {
            name           = "http"
            container_port = 8080
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "384Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "1Gi"
            }
          }

          # The image's own binary carries cap_net_bind_service, so port
          # 25 binds without root -- but that file capability only takes
          # effect if the capability is in the bounding set, so only the
          # rest are dropped.
          security_context {
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 2000
            run_as_group               = 2000
            capabilities {
              drop = ["ALL"]
              add  = ["NET_BIND_SERVICE"]
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/etc/stalwart"
            sub_path   = "etc"
          }
          volume_mount {
            name       = "data"
            mount_path = "/var/lib/stalwart"
            sub_path   = "data"
          }

          # Deliberately only a startup probe, on 8080 -- see
          # current-state.md for why steady-state probes are left for a
          # follow-up.
          startup_probe {
            tcp_socket {
              port = 8080
            }
            period_seconds    = 5
            timeout_seconds   = 3
            failure_threshold = 30
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.stalwart.metadata[0].name
          }
        }
      }
    }
  }
}

# Public mail ports: inbound SMTP (25), plus the TLS-only client ports
# IMAPS (993) and implicit-TLS submission (465) for mail clients. The
# plaintext 143/587 are deliberately not exposed. The name stays
# "stalwart-smtp" (renaming would replace the Service and its
# LoadBalancer address) though it now carries more than SMTP.
# Local, so the real client/sender IP reaches Stalwart for SPF, rate
# limiting and its brute-force protection -- the same reason as
# modules/blocky's own Service: the default (Cluster) masquerades the
# source. Safe because the single replica and this Service's
# LoadBalancer IP share k3s-node-1.
resource "kubernetes_service_v1" "stalwart_smtp" {
  metadata {
    name = "stalwart-smtp"
  }

  wait_for_load_balancer = false

  spec {
    type                    = "LoadBalancer"
    external_traffic_policy = "Local"

    selector = {
      app = "stalwart"
    }

    port {
      name        = "smtp"
      port        = 25
      target_port = 25
    }
    port {
      name        = "imaps"
      port        = 993
      target_port = 993
    }
    port {
      name        = "submissions"
      port        = 465
      target_port = 465
    }
  }
}

# In-cluster only: the web admin/wizard (reach via kubectl port-forward).
resource "kubernetes_service_v1" "stalwart_internal" {
  metadata {
    name = "stalwart-internal"
  }

  spec {
    type = "ClusterIP"

    selector = {
      app = "stalwart"
    }

    port {
      name        = "http"
      port        = 8080
      target_port = 8080
    }
  }
}
