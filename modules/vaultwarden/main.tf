# Vaultwarden (ADR 0028): features beyond the personal vault are off, and so is all egress.

locals {
  backend_url = "http://${kubernetes_service_v1.vaultwarden.metadata[0].name}:${kubernetes_service_v1.vaultwarden.spec[0].port[0].port}"

  env = {
    DOMAIN          = "https://vault.jkandler.de"
    DATA_FOLDER     = "/data"
    ROCKET_PORT     = "8080"
    SIGNUPS_ALLOWED = tostring(var.initial_signup)
    # Unset ADMIN_TOKEN already disables /admin; never set DISABLE_ADMIN_TOKEN.
    INVITATIONS_ALLOWED      = "false"
    ORG_CREATION_USERS       = "none"
    SENDS_ALLOWED            = "false"
    EMERGENCY_ACCESS_ALLOWED = "false"
    PASSWORD_HINTS_ALLOWED   = "false"
    SHOW_PASSWORD_HINT       = "false"
    DISABLE_ICON_DOWNLOAD    = "true"
    USER_ATTACHMENT_LIMIT    = "0"
    ORG_ATTACHMENT_LIMIT     = "0"
    PUSH_ENABLED             = "false"
    # Traefik sets X-Real-Ip from the real client since the ingress keeps source IPs.
    IP_HEADER                 = "X-Real-IP"
    LOGIN_RATELIMIT_SECONDS   = "60"
    LOGIN_RATELIMIT_MAX_BURST = "10"
    LOG_LEVEL                 = "warn"
  }
}

resource "kubernetes_deployment_v1" "vaultwarden" {
  metadata {
    namespace = "apps"
    name      = "vaultwarden"
  }

  spec {
    replicas = 1

    # Two Pods on one SQLite file corrupt it.
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "vaultwarden"
      }
    }

    template {
      metadata {
        labels = {
          app = "vaultwarden"
        }
      }

      spec {
        automount_service_account_token = false

        security_context {
          # The provider otherwise sends false, which the restricted level rejects.
          run_as_non_root = true
          fs_group        = 1000

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "vaultwarden"
          image = "ghcr.io/dani-garcia/vaultwarden:1.37.5-alpine@sha256:bbe684a02d6b0db54256ff88eac9754f4519284a7b26314afc241fd7d0918191"

          port {
            name           = "http"
            container_port = 8080
          }

          dynamic "env" {
            for_each = local.env
            content {
              name  = env.key
              value = env.value
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

          security_context {
            read_only_root_filesystem  = true
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 1000
            run_as_group               = 1000
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "data"
            mount_path = "/data"
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          readiness_probe {
            http_get {
              path = "/alive"
              port = 8080
            }
            period_seconds    = 10
            timeout_seconds   = 5
            failure_threshold = 3
          }
          liveness_probe {
            http_get {
              path = "/alive"
              port = 8080
            }
            initial_delay_seconds = 10
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 3
          }
        }

        volume {
          name = "data"
          persistent_volume_claim {
            claim_name = module.vaultwarden_data.name
          }
        }
        volume {
          name = "tmp"
          empty_dir {
            medium     = "Memory"
            size_limit = "16Mi"
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "vaultwarden" {
  metadata {
    namespace = "apps"
    name      = "vaultwarden-svc"
  }

  spec {
    selector = {
      app = "vaultwarden"
    }

    port {
      port        = 80
      target_port = 8080
    }
  }
}

# Only Traefik gets in; out, only cluster DNS (no icons, push, mail or HIBP lookups).
resource "kubernetes_network_policy_v1" "vaultwarden" {
  metadata {
    namespace = "apps"
    name      = "vaultwarden"
  }

  spec {
    pod_selector {
      match_labels = {
        app = "vaultwarden"
      }
    }

    policy_types = ["Ingress", "Egress"]

    ingress {
      from {
        pod_selector {
          match_labels = {
            app = "ingress"
          }
        }
      }
      ports {
        port     = "8080"
        protocol = "TCP"
      }
    }

    egress {
      to {
        namespace_selector {
          match_labels = {
            "kubernetes.io/metadata.name" = "kube-system"
          }
        }
        pod_selector {
          match_labels = {
            k8s-app = "kube-dns"
          }
        }
      }
      ports {
        port     = "53"
        protocol = "UDP"
      }
      ports {
        port     = "53"
        protocol = "TCP"
      }
    }
  }
}
