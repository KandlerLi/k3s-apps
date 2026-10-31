locals {
  image = "ghcr.io/home-operations/qbittorrent:5.3.0@sha256:5a858e61f94cf2712391db32ed03556576c700858f3e62c4c6fcde262443ebd8"
}

# No secrets in it: the Web UI skips its login for Traefik, which the NetworkPolicy below enforces.
resource "kubernetes_config_map_v1" "config" {
  metadata {
    namespace = "apps"
    name      = "qbittorrent-config"
  }

  data = {
    "qBittorrent.conf" = file("${path.module}/qBittorrent.conf")
  }
}

resource "kubernetes_deployment_v1" "qbittorrent" {
  metadata {
    namespace = "apps"
    name      = "qbittorrent"
  }

  spec {
    replicas = 1

    # One instance per config/state.
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "qbittorrent"
      }
    }

    template {
      metadata {
        labels = {
          app = "qbittorrent"
        }
        annotations = {
          "checksum/config" = sha256(kubernetes_config_map_v1.config.data["qBittorrent.conf"])
        }
      }

      spec {
        # Doesn't talk to the Kubernetes API.
        automount_service_account_token = false

        security_context {
          # The provider otherwise sends false, which the restricted level rejects.
          run_as_non_root = true

          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        # qBittorrent rewrites its config on exit, so it's overwritten on every start to keep Terraform authoritative.
        init_container {
          name    = "write-config"
          image   = local.image
          command = ["sh", "-c", "mkdir -p /config/qBittorrent && cp /config-source/qBittorrent.conf /config/qBittorrent/qBittorrent.conf"]

          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            run_as_user                = 993
            run_as_group               = 986
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/config"
          }
          volume_mount {
            name       = "config-source"
            mount_path = "/config-source"
            read_only  = true
          }
        }

        container {
          name  = "qbittorrent"
          image = local.image

          env {
            name  = "TZ"
            value = "Etc/UTC"
          }

          # Like home-infra's deluge account, which owns the NFS exports.
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            run_as_user                = 993
            run_as_group               = 986
            capabilities {
              drop = ["ALL"]
            }
          }

          port {
            name           = "web"
            container_port = 8080
          }
          port {
            name           = "peer-tcp"
            container_port = 6881
            protocol       = "TCP"
          }
          port {
            name           = "peer-udp"
            container_port = 6881
            protocol       = "UDP"
          }

          resources {
            limits = {
              memory = "512Mi"
              cpu    = "1000m"
            }
          }

          # exec, not httpGet: the NetworkPolicy admits only Traefik to the Web UI port.
          readiness_probe {
            exec {
              command = ["curl", "-fsS", "-o", "/dev/null", "-H", "Host: torrent.jkandler.de", "http://127.0.0.1:8080/api/v2/app/version"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 5
          }

          volume_mount {
            name       = "config"
            mount_path = "/config"
          }
          volume_mount {
            name       = "downloads"
            mount_path = "/downloads"
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }
        }

        # Deluge's config volume: qBittorrent keeps to its own qBittorrent/ and .cache/ there, Deluge's files stay for a rollback.
        volume {
          name = "config"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.deluge_config.metadata[0].name
          }
        }
        volume {
          name = "downloads"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.deluge_downloads.metadata[0].name
          }
        }
        volume {
          name = "config-source"
          config_map {
            name = kubernetes_config_map_v1.config.metadata[0].name
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

resource "kubernetes_service_v1" "web" {
  metadata {
    namespace = "apps"
    name      = "qbittorrent-web-svc"
  }

  spec {
    selector = {
      app = "qbittorrent"
    }

    port {
      port        = 80
      target_port = 8080
    }
  }
}

# Peer traffic isn't HTTP, so a LoadBalancer on a fixed port.
resource "kubernetes_service_v1" "peer" {
  metadata {
    namespace = "apps"
    name      = "qbittorrent-peer-svc"
  }

  spec {
    type = "LoadBalancer"

    selector = {
      app = "qbittorrent"
    }

    port {
      name        = "peer-tcp"
      protocol    = "TCP"
      port        = 6881
      target_port = 6881
    }
    port {
      name        = "peer-udp"
      protocol    = "UDP"
      port        = 6881
      target_port = 6881
    }
  }
}

# The Web UI trusts the whole pod CIDR without a login, so only Traefik may reach it.
resource "kubernetes_network_policy_v1" "qbittorrent" {
  metadata {
    namespace = "apps"
    name      = "qbittorrent"
  }

  spec {
    pod_selector {
      match_labels = {
        app = "qbittorrent"
      }
    }

    policy_types = ["Ingress"]

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

    ingress {
      ports {
        port     = "6881"
        protocol = "TCP"
      }
      ports {
        port     = "6881"
        protocol = "UDP"
      }
    }
  }
}
