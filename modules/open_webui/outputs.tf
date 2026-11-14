output "ingress_routes" {
  description = "Traefik routes for modules/ingress (see its routes variable)."
  value = {
    # No forward-auth: Open WebUI does its own Authelia OIDC login.
    open-webui = {
      rule           = "Host(`ai.jkandler.de`)"
      priority       = 10
      url            = "http://open-webui-svc:80"
      forward_auth   = false
      rate_limit     = { average = 120, burst = 240 }
      max_body_bytes = 1048576
    }
  }
}
