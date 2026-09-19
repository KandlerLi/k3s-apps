# Stalwart mail server, first slice: inbound SMTP (port 25) only. The
# homeserver's k3s_ingress_forward relay (home-infra#51) already carries
# public port 25 to this Service's LoadBalancer address; submission,
# IMAP and the web admin stay cluster-internal for now (reach the admin
# with `kubectl port-forward svc/stalwart-internal 8080`).
#
# First-run setup is done through Stalwart's own bootstrap wizard, which
# generates config.toml on the PVC and prints a temporary admin password
# to the Pod log (`kubectl logs deploy/stalwart | grep -A8 'bootstrap
# mode'`). STALWART_RECOVERY_ADMIN (a fixed admin credential) is
# deliberately not wired yet: it needs a new Secrets Manager entry in
# aws/secrets-manager first, a separate change.
#
# Image: v0.16.22, pinned by digest like every other module here.
#
# Sizing: the setup wizard's RocksDB defaults (128MB write buffers + 128MB
# block cache) alone are ~256MB before Stalwart's own process, so the
# original 512Mi limit sat right at the OOM line. The limit is what
# matters (the node itself has free memory); request stays modest.
# Revisit against real usage once mail actually flows.

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

          port {
            name           = "smtp"
            container_port = 25
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

          # Deliberately only a startup probe, on 8080. Confirmed live
          # (2026-09-19): until the bootstrap wizard is completed,
          # Stalwart listens on 8080 only -- no SMTP listener at all --
          # so the original readiness/liveness probes on port 25 failed
          # forever, and the liveness probe restarted the Pod every ~3
          # minutes (the CI apply then timed out waiting for Ready).
          # Which ports stay open after setup isn't known yet, so a
          # steady-state readiness/liveness probe is left for a
          # follow-up once the real listeners are known; a wrong one
          # here would either kill or unroute a working mail server.
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

# Public inbound SMTP only. Local, so the real sender IP reaches Stalwart
# for SPF and rate limiting -- the same reason as modules/blocky's own
# Service: the default (Cluster) masquerades the source. Safe because
# the single replica and this Service's LoadBalancer IP share k3s-node-1.
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
