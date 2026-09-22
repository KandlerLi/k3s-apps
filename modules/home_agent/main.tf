# home_agent + nextcloud_tools as sidecars in one Pod, sharing a Unix
# socket through an emptyDir -- nextcloud_tools stays reachable only
# over that socket, never a network. home_tools_service is the one
# dependency that couldn't move this way -- reached over a TCP listener
# at 192.168.101.1:8095 instead. Full cutover history and every bug
# found: docs/home-infra-ai-context's current-state.md ("k3s learning
# cluster").

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

        # Same checksum-annotation pattern as modules/grafana/
        # modules/alertmanager -- forces a rollout on rotation instead
        # of leaving whether the process notices unconfirmed.
        annotations = {
          "checksum/openai-api-key"         = sha256(kubernetes_secret_v1.openai_api_key.data["openai_api_key"])
          "checksum/anthropic-api-key"      = sha256(kubernetes_secret_v1.anthropic_api_key.data["anthropic_api_key"])
          "checksum/nextcloud-app-password" = sha256(kubernetes_secret_v1.nextcloud_tools_app_password.data["app-password"])
          # A ConfigMap change alone never restarts the sidecar that
          # mounts it, so hash its script here to force a rollout
          # whenever files/nextcloud_tools_service.py changes.
          "checksum/nextcloud-tools-source" = sha256(file("${path.module}/files/nextcloud_tools_service.py"))
        }
      }

      spec {
        # Neither container talks to the Kubernetes API. See
        # current-state.md for the /run/secrets collision this avoids.
        automount_service_account_token = false

        image_pull_secrets {
          name = module.ghcr_pull_secret.name
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

          # I/O-bound (waiting on network calls, not burning CPU) -- see
          # current-state.md for the scheduling failure an unmeasured
          # 1000m limit caused.
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
          # The agent sees every folder Julian explicitly shares with
          # the home-agent account, and nothing else -- scope and
          # read-only vs. editable are decided per share in Nextcloud
          # itself, never here.
          env {
            name  = "NEXTCLOUD_ALLOWED_ROOT"
            value = "Shared"
          }

          # Same over-provisioning fix as the home-agent container above --
          # this is a stdlib-only socket relay to Nextcloud's WebDAV API,
          # not something that needs half a core.
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
            # Shares home-agent's own GID (10001), not this container's
            # own UID's group -- the socket this process creates and
            # chmods 0660 needs to be group-readable/writable by
            # home-agent's process specifically. See current-state.md.
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
