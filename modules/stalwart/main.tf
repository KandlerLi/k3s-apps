# Stalwart mail server; the web admin stays cluster-internal. See history.md ("Mail server").

# The SES relay credential via environment variables, rotatable, instead of typed into Stalwart's UI.
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

        # Volume ownership for the image's UID 2000.
        security_context {
          fs_group = 2000
        }

        container {
          name  = "stalwart"
          image = "stalwartlabs/stalwart:v0.16.22@sha256:388dcb75a70727c5b551249a6d34b1f1321294852489e4fa3a4e6be698b7c4f0"

          # The public base URL, so redirects and JMAP session URLs use it.
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

          # The binary's cap_net_bind_service needs that capability in the bounding set.
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

          # Startup probe only: see history.md.
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

# 25, 993 and 465 only; the name stays, renaming would change the LoadBalancer address. Local keeps the client IP.
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
