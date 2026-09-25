# Dedicated Traefik Deployment -- k3s's own bundled instance stays
# disabled (k3s_node's one departure from "everything else stays at
# defaults"). The iptables DNAT relay that gets public traffic to this
# cluster at all lives in home-infra's k3s_ingress_forward role, not
# here. Full migration history and the DNS-01-over-TLS-ALPN-01 ACME
# decision: docs/home-infra-ai-context's current-state.md ("k3s
# learning cluster").

resource "kubernetes_deployment_v1" "ingress" {
  metadata {
    name = "ingress"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "ingress"
      }
    }

    template {
      metadata {
        labels = {
          app = "ingress"
        }

        # sub_path mounts and secretKeyRef env vars never live-refresh
        # on a ConfigMap/Secret change -- Kubernetes only picks up new
        # content on a real Pod recreation. These checksums force that
        # recreation whenever any of the three sources actually
        # changes. See current-state.md for the incidents that found
        # this the hard way.
        annotations = {
          "checksum/static-config"          = sha256(kubernetes_config_map_v1.ingress_static_config.data["traefik.yml"])
          "checksum/dynamic-config"         = sha256(kubernetes_config_map_v1.ingress_dynamic_config.data["routes.yml"])
          "checksum/acme-dns01-credentials" = sha256(jsonencode(kubernetes_secret_v1.ingress_acme_dns01_credentials.data))
        }
      }

      spec {
        # Doesn't talk to the Kubernetes API.
        automount_service_account_token = false

        container {
          name  = "traefik"
          image = "traefik:v3.7.1@sha256:6b9cbca6fac42ab0075f5437d8dc1685cfd188626d8d515839ea94f8b6271c42"

          args = [
            "--configFile=/etc/traefik/traefik.yml",
          ]

          # lego's own route53 provider reads these directly from the
          # environment. Zone ID/region are non-secret literals;
          # setting AWS_HOSTED_ZONE_ID explicitly also skips lego's own
          # zone-lookup call, matching the IAM user's narrow policy.
          env {
            name  = "AWS_HOSTED_ZONE_ID"
            value = "Z07879811I86VC8PAL8HX"
          }
          env {
            name  = "AWS_REGION"
            value = "eu-central-1"
          }
          env {
            name = "AWS_ACCESS_KEY_ID"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.ingress_acme_dns01_credentials.metadata[0].name
                key  = "AWS_ACCESS_KEY_ID"
              }
            }
          }
          env {
            name = "AWS_SECRET_ACCESS_KEY"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.ingress_acme_dns01_credentials.metadata[0].name
                key  = "AWS_SECRET_ACCESS_KEY"
              }
            }
          }

          port {
            name           = "web"
            container_port = 80
          }
          port {
            name           = "websecure"
            container_port = 443
          }
          port {
            name           = "health"
            container_port = 8082
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

          # NET_BIND_SERVICE is the one added capability -- needed to
          # bind ports 80/443 as a non-root user.
          security_context {
            read_only_root_filesystem  = true
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 65534
            run_as_group               = 65534
            capabilities {
              drop = ["ALL"]
              add  = ["NET_BIND_SERVICE"]
            }
          }

          volume_mount {
            name       = "static-config"
            mount_path = "/etc/traefik/traefik.yml"
            sub_path   = "traefik.yml"
            read_only  = true
          }
          volume_mount {
            name       = "dynamic-config"
            mount_path = "/etc/traefik/dynamic/routes.yml"
            sub_path   = "routes.yml"
            read_only  = true
          }
          volume_mount {
            name       = "acme"
            mount_path = "/letsencrypt"
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          readiness_probe {
            http_get {
              path = "/ping"
              port = 8082
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 3
          }
          liveness_probe {
            http_get {
              path = "/ping"
              port = 8082
            }
            initial_delay_seconds = 10
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 3
          }
        }

        volume {
          name = "static-config"
          config_map {
            name = kubernetes_config_map_v1.ingress_static_config.metadata[0].name
          }
        }
        volume {
          name = "dynamic-config"
          config_map {
            name = kubernetes_config_map_v1.ingress_dynamic_config.metadata[0].name
          }
        }
        volume {
          name = "acme"
          persistent_volume_claim {
            claim_name = module.ingress_acme.name
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

# type = LoadBalancer -- k3s's bundled ServiceLB binds this to
# k3s-node-1's own address, giving home-infra's k3s_ingress_forward
# role a stable 192.168.101.10:80/:443 DNAT target.
#
# wait_for_load_balancer = false: k3s's bundled Traefik holds these
# same ports until it's disabled, so ServiceLB can't assign this
# Service an external IP until then -- see current-state.md.
resource "kubernetes_service_v1" "ingress" {
  metadata {
    name = "ingress-svc"
  }

  wait_for_load_balancer = false

  spec {
    type = "LoadBalancer"

    selector = {
      app = "ingress"
    }

    port {
      name        = "web"
      port        = 80
      target_port = 80
    }
    port {
      name        = "websecure"
      port        = 443
      target_port = 443
    }
  }
}
