output "ingress_routes" {
  description = "Traefik routes for modules/ingress (see its routes variable)."
  value = {
    # Only the API paths; the rest of the host is Open WebUI, hence the higher priority.
    home-agent-api = {
      rule           = "Host(`ai.jkandler.de`) && (Path(`/healthz`) || Path(`/v1/chat`))"
      priority       = 100
      url            = "http://home-agent-svc:80"
      forward_auth   = true
      rate_limit     = { average = 10, burst = 5 }
      max_body_bytes = 16384
    }
  }
}
