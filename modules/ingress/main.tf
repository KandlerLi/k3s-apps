# Phase [shared_ingress migration] (see the approved plan in
# home-infra's own plan history): the last, highest-stakes piece of
# the "move things to k3s one at a time" project. Unlike every prior
# migration, this one has no safe additive window -- only one thing can
# hold the homeserver's own physical ports 80/443 at a time. See the
# plan itself for the full reasoning; this module only covers the
# in-cluster half of it (the new Traefik instance). The other half --
# the iptables DNAT relay that actually gets public traffic here at
# all, since the k3s VM's own network is deliberately unreachable from
# the LAN otherwise -- lives in home-infra's new k3s_ingress_forward
# role, not here.
#
# A new, dedicated Traefik, not a reconfiguration of k3s's own bundled
# one -- k3s_node's own README deliberately keeps that at defaults, and
# real production ACME/Basic-Auth/rate-limit config has no business
# living there. k3s's own bundled Traefik is disabled entirely
# (k3s_node's own --disable traefik flag) once this one is confirmed
# taking over cleanly -- two Traefik instances can't both hold the
# same LoadBalancer ports or usefully watch the same Ingress resources.
#
# Static/dynamic config (configmap.tf) mirrors home-infra's own
# shared_ingress role's templates nearly verbatim, deliberately -- the
# lowest-risk possible translation on the riskiest service in this
# project, reusing config already proven in production rather than
# learning Kubernetes' own IngressRoute/Middleware CRD model here of
# all places. Every backend routes to this cluster's own in-cluster
# Service DNS names directly now (home-agent-svc, open-webui-svc,
# deluge-web-svc, grafana-svc, landing-page-svc), not back out through
# the node's own external address the way the old, outside-the-cluster
# homeserver Traefik had to -- this Traefik lives inside the cluster
# now, so it doesn't need to.
#
# Resources: no real usage data for this exact workload yet (first
# deploy of a from-scratch Traefik instance, not a migrated one with
# its own docker stats history) -- limits match the old Docker
# container's own ceiling (256Mi/0.5 CPU) as a starting point, requests
# set conservatively low; revisit against real usage once live, the
# same measure-then-size discipline every other module here follows
# once real data exists to size from.

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

          # lego's own route53 provider (the ACME DNS-01 challenge --
          # see configmap.tf's own comment) reads all of these directly
          # from the environment. AWS_HOSTED_ZONE_ID/AWS_REGION are
          # non-secret (dyndns's own public jkandler.de zone ID, same
          # region dyndns itself deploys into) so they're literals here
          # rather than SOPS secrets -- passing AWS_HOSTED_ZONE_ID
          # explicitly also skips lego's own route53:ListHostedZonesByName
          # zone-lookup call entirely, matching the IAM user's own
          # deliberately narrow policy (see dyndns's own main.tf).
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

          # Matches the old Docker container's own security_opts/
          # cap_drop/capabilities exactly: read-only root, every
          # capability dropped except NET_BIND_SERVICE (needed to bind
          # ports 80/443 as a non-root user -- otherwise the kernel's
          # own unprivileged-port restriction blocks it).
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
            name       = "users"
            mount_path = "/etc/traefik/users"
            sub_path   = "users"
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
          name = "users"
          secret {
            secret_name = kubernetes_secret_v1.ingress_users.metadata[0].name
          }
        }
        volume {
          name = "acme"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.ingress_acme.metadata[0].name
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

# type = LoadBalancer, matching modules/deluge's/modules/alertmanager's
# own precedent -- k3s's bundled ServiceLB binds this directly to
# k3s-node-1's own address, giving home-infra's new
# k3s_ingress_forward role a stable 192.168.101.10:80/:443 DNAT target.
#
# wait_for_load_balancer = false: confirmed live that this resource
# hangs indefinitely (Terraform's own default wait behavior for
# LoadBalancer Services) without it -- k3s's own bundled Traefik is
# still running as this module's own first apply, already holding
# these exact ports on this exact node via its own svclb-traefik Pod,
# so ServiceLB can never assign this Service an external IP until that
# one is disabled. Deliberately not disabling it yet -- confirmed live
# it's still routing real production traffic today (ai/torrent/
# grafana/home.jkandler.de all forward through it already), so this
# module gets built, wired, and verified via its own ClusterIP first;
# disabling k3s's bundled Traefik is its own separate, deliberate step.
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
