# home_agent and nextcloud_tools share a Unix socket in one Pod; nextcloud_tools is never on the network.

resource "kubernetes_deployment_v1" "home_agent" {
  metadata {
    namespace = "apps"
    name      = "home-agent"
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

        # Checksums force a rollout on rotation.
        annotations = {
          "checksum/openai-api-key"         = sha256(kubernetes_secret_v1.openai_api_key.data["openai_api_key"])
          "checksum/anthropic-api-key"      = sha256(kubernetes_secret_v1.anthropic_api_key.data["anthropic_api_key"])
          "checksum/nextcloud-app-password" = sha256(kubernetes_secret_v1.nextcloud_tools_app_password.data["app-password"])
          # A ConfigMap change alone never restarts the sidecar.
          "checksum/nextcloud-tools-source" = sha256(file("${path.module}/files/nextcloud_tools_service.py"))
        }
      }

      spec {
        # Neither container talks to the Kubernetes API.
        automount_service_account_token = false

        image_pull_secrets {
          name = module.ghcr_pull_secret.name
        }

        security_context {
          # The provider otherwise sends false, which the restricted level rejects.
          run_as_non_root = true

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "home-agent"
          image = var.home_agent_image

          env {
            name  = "HOME_AGENT_MODEL"
            value = "claude-opus-5"
          }
          env {
            name  = "HOME_AGENT_STT_MODEL"
            value = "whisper-1"
          }
          env {
            name  = "ANTHROPIC_API_KEY_FILE"
            value = "/run/secrets/anthropic/anthropic_api_key"
          }
          env {
            name  = "OPENAI_API_KEY_FILE"
            value = "/run/secrets/openai/openai_api_key"
          }
          env {
            name  = "NEXTCLOUD_TOOLS_SOCKET"
            value = "/run/nextcloud-tools/nextcloud-tools.sock"
          }
          # Switches HomeToolsClient to TCP.
          env {
            name  = "HOME_TOOLS_TCP_BASE_URL"
            value = "http://192.168.101.1:8095"
          }

          port {
            name           = "http"
            container_port = 8000
          }

          # I/O-bound: a small CPU request.
          resources {
            limits = {
              memory = "256Mi"
              cpu    = "250m"
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
            mount_path = "/run/secrets/openai"
            read_only  = true
          }
          volume_mount {
            name       = "anthropic-api-key"
            mount_path = "/run/secrets/anthropic"
            read_only  = true
          }
          volume_mount {
            name       = "home-agent-tmp"
            mount_path = "/tmp"
          }
        }

        container {
          name    = "nextcloud-tools"
          image   = "python:3.13-slim-trixie@sha256:2d44738ebf4ce5f63b9d9ea871e9c7cfdc0426f7b0c97cac915fd88ded1d86bb"
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
          # The homeserver's k3s-network address; must match home-infra's nextcloud_aio_apache_ip_binding.
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
          # Scope is whatever Julian shares with the home-agent account in Nextcloud.
          env {
            name  = "NEXTCLOUD_ALLOWED_ROOT"
            value = "Shared"
          }

          # A stdlib socket relay: a small CPU request.
          resources {
            limits = {
              memory = "128Mi"
              cpu    = "100m"
            }
          }

          security_context {
            read_only_root_filesystem  = true
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 10002
            # home-agent's GID, so the 0660 socket is reachable for it.
            run_as_group = 10001
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
          name = "anthropic-api-key"
          secret {
            secret_name = kubernetes_secret_v1.anthropic_api_key.metadata[0].name
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
    namespace = "apps"
    name      = "home-agent-svc"
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
