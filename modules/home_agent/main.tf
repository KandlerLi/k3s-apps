# home_agent + nextcloud_tools as sidecars in one Pod, sharing a Unix
# socket through an emptyDir -- preserves the exact trust shape
# home-infra's own deployment already has (nextcloud_tools reachable
# only over a Unix socket, never a network), just relocated from "two
# processes on one host" to "two containers in one Pod". home_tools_service
# is the one dependency that couldn't move this way (see home-infra's
# own comment on home_agent_tools_tcp_bind_address) -- it's reached over
# its new TCP listener instead, at 192.168.101.1:8095.
#
# No Ingress here yet -- home_agent doesn't need to be reachable on its
# own; only open_webui (not yet migrated) needs to reach it, the same
# internal-only relationship home-infra's own home-agent-frontend Docker
# network already has today.

resource "kubernetes_deployment_v1" "home_agent" {
  metadata {
    name = "home-agent"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "home-agent"
      }
    }

    template {
      metadata {
        labels = {
          app = "home-agent"
        }
      }

      spec {
        image_pull_secrets {
          name = kubernetes_secret_v1.ghcr_pull.metadata[0].name
        }

        container {
          name  = "home-agent"
          image = var.home_agent_image

          env {
            name  = "HOME_AGENT_MODEL"
            value = "gpt-5.4-mini"
          }
          env {
            name  = "HOME_AGENT_STT_MODEL"
            value = "whisper-1"
          }
          env {
            name  = "OPENAI_API_KEY_FILE"
            value = "/run/secrets/openai_api_key"
          }
          env {
            name  = "NEXTCLOUD_TOOLS_SOCKET"
            value = "/run/nextcloud-tools/nextcloud-tools.sock"
          }
          # Takes precedence over the (unset) Unix socket path in
          # create_provider() -- switches HomeToolsClient to plain TCP,
          # see home-infra's unix_socket_client.py/home_tools.py/api.py.
          env {
            name  = "HOME_TOOLS_TCP_BASE_URL"
            value = "http://192.168.101.1:8095"
          }

          port {
            name           = "http"
            container_port = 8000
          }

          resources {
            limits = {
              memory = "256Mi"
              cpu    = "1000m"
            }
          }

          security_context {
            read_only_root_filesystem  = true
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 10001
            run_as_group               = 10001
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "nextcloud-tools-socket"
            mount_path = "/run/nextcloud-tools"
            read_only  = true
          }
          volume_mount {
            name       = "openai-api-key"
            mount_path = "/run/secrets"
            read_only  = true
          }
          volume_mount {
            name       = "home-agent-tmp"
            mount_path = "/tmp"
          }
        }

        container {
          name    = "nextcloud-tools"
          image   = "python:3.13-slim-bookworm"
          command = ["python3", "/app/nextcloud_tools_service.py"]

          env {
            name  = "PYTHONUNBUFFERED"
            value = "1"
          }
          env {
            name  = "PYTHONDONTWRITEBYTECODE"
            value = "1"
          }
          env {
            name  = "NEXTCLOUD_TOOLS_SOCKET"
            value = "/run/nextcloud-tools/nextcloud-tools.sock"
          }
          # This homeserver's own address on the k3s VM's isolated
          # network -- see nextcloud_aio_apache_ip_binding's own comment
          # in home-infra for the full reasoning; must stay in lockstep
          # with that value.
          env {
            name  = "NEXTCLOUD_ENDPOINT_HOST"
            value = "192.168.101.1"
          }
          env {
            name  = "NEXTCLOUD_ENDPOINT_PORT"
            value = "11000"
          }
          env {
            name  = "NEXTCLOUD_HTTP_HOST"
            value = "nextcloud.jkandler.de"
          }
          env {
            name  = "NEXTCLOUD_USERNAME"
            value = "home-agent"
          }
          env {
            name  = "NEXTCLOUD_APP_PASSWORD_FILE"
            value = "/etc/nextcloud-tools/app-password"
          }
          # The real live value (not the role's own bare "AI Workspace"
          # default) -- Nextcloud shares don't preserve the sharer's own
          # path for the recipient, confirmed live via `occ
          # share:list --recipient=home-agent`, same lesson learned for
          # sankey_export's own remote_dir.
          env {
            name  = "NEXTCLOUD_ALLOWED_ROOT"
            value = "Shared/AI Workspace"
          }

          resources {
            limits = {
              memory = "128Mi"
              cpu    = "500m"
            }
          }

          security_context {
            read_only_root_filesystem  = true
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 10002
            run_as_group               = 10002
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "nextcloud-tools-source"
            mount_path = "/app"
            read_only  = true
          }
          volume_mount {
            name       = "nextcloud-tools-socket"
            mount_path = "/run/nextcloud-tools"
          }
          volume_mount {
            name       = "nextcloud-tools-app-password"
            mount_path = "/etc/nextcloud-tools"
            read_only  = true
          }
          volume_mount {
            name       = "nextcloud-tools-tmp"
            mount_path = "/tmp"
          }
        }

        volume {
          name = "nextcloud-tools-socket"
          empty_dir {}
        }
        volume {
          name = "home-agent-tmp"
          empty_dir {}
        }
        volume {
          name = "nextcloud-tools-tmp"
          empty_dir {}
        }
        volume {
          name = "openai-api-key"
          secret {
            secret_name = kubernetes_secret_v1.openai_api_key.metadata[0].name
          }
        }
        volume {
          name = "nextcloud-tools-app-password"
          secret {
            secret_name = kubernetes_secret_v1.nextcloud_tools_app_password.metadata[0].name
          }
        }
        volume {
          name = "nextcloud-tools-source"
          config_map {
            name = kubernetes_config_map_v1.nextcloud_tools_source.metadata[0].name
          }
        }
      }
    }
  }
}

resource "kubernetes_service_v1" "home_agent" {
  metadata {
    name = "home-agent-svc"
  }

  spec {
    selector = {
      app = "home-agent"
    }

    port {
      port        = 80
      target_port = 8000
    }
  }
}
