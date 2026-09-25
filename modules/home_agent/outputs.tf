output "ingress_routes" {
  description = "Traefik routes for modules/ingress (see its routes variable)."
  value = {
    # Only the API paths; everything else on this host is Open WebUI
    # (modules/open_webui), hence the higher priority.
    home-agent-api = {
      rule           = "Host(`ai.jkandler.de`) && (Path(`/healthz`) || Path(`/v1/chat`))"
      priority       = 100
      url            = "http://${kubernetes_service_v1.home_agent.metadata[0].name}:${kubernetes_service_v1.home_agent.spec[0].port[0].port}"
      forward_auth   = true
      rate_limit     = { average = 10, burst = 5 }
      max_body_bytes = 16384
    }
  }
}
