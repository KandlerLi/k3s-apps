# ai.jkandler.de -- one hostname split by path between home_agent and
# open_webui, exactly like home-infra's own shared_ingress does today
# (see its dynamic.yml.j2: home_agent answers /healthz and /v1/chat
# directly, priority 100; open_webui gets everything else, priority
# 10). shared_ingress' own two upstreams (shared_ingress_agent_upstream,
# shared_ingress_open_webui_upstream) both point at this cluster's
# Traefik once cut over, so this Ingress has to replicate that same
# split on this side -- standard Kubernetes Ingress path matching
# already prefers a more specific (Exact) match over a broader
# (Prefix) one for the same host, without needing Traefik's own
# priority annotation the Docker-side config uses.
#
# Lives at the root, not inside either module -- it's the one thing
# that genuinely depends on both home_agent's and open_webui's own
# Services, which Terraform can only reference across modules through
# their outputs.tf.

resource "kubernetes_ingress_v1" "ai" {
  metadata {
    name = "ai-ingress"
  }

  spec {
    ingress_class_name = "traefik"

    rule {
      # shared_ingress' own outer Traefik forwards the client's
      # original Host header unchanged (passHostHeader: true), so this
      # has to match what actually arrives once home-infra points both
      # ai.jkandler.de upstreams at this cluster.
      host = "ai.jkandler.de"

      http {
        path {
          path      = "/healthz"
          path_type = "Exact"

          backend {
            service {
              name = module.home_agent.service_name

              port {
                number = 80
              }
            }
          }
        }

        path {
          path      = "/v1/chat"
          path_type = "Exact"

          backend {
            service {
              name = module.home_agent.service_name

              port {
                number = 80
              }
            }
          }
        }

        path {
          path      = "/"
          path_type = "Prefix"

          backend {
            service {
              name = module.open_webui.service_name

              port {
                number = 80
              }
            }
          }
        }
      }
    }
  }
}
