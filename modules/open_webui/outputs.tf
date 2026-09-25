output "ingress_routes" {
  description = "Traefik routes for modules/ingress (see its routes variable)."
  value = {
    # No forward-auth: Open WebUI does its own Authelia OIDC login.
    open-webui = {
      rule           = "Host(`ai.jkandler.de`)"
      priority       = 10
      url            = "http://${kubernetes_service_v1.open_webui.metadata[0].name}:${kubernetes_service_v1.open_webui.spec[0].port[0].port}"
      forward_auth   = false
      rate_limit     = { average = 120, burst = 240 }
      max_body_bytes = 1048576
    }
  }
}
