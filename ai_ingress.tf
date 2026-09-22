# ai.jkandler.de -- one hostname split by path between home_agent and
# open_webui (home_agent answers /healthz and /v1/chat, open_webui gets
# everything else). Lives at the root, not inside either module -- it's
# the one thing that depends on both home_agent's and open_webui's own
# Services, referenced across modules through their outputs.tf.
#
# NOTE (found during a 2026-09-22 comment-trim pass, not yet acted on):
# same as modules/deluge's/modules/grafana's/modules/landing_page's own
# kubernetes_ingress_v1 resources -- ai.jkandler.de's real routing now
# happens via modules/ingress's own home-agent-api/open-webui routers
# (configmap.tf), and this Ingress looks like it's no longer read by
# anything since that Traefik only has a `file` provider configured.

resource "kubernetes_ingress_v1" "ai" {
  metadata {
    name = "ai-ingress"
  }

  spec {
    ingress_class_name = "traefik"

    rule {
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
