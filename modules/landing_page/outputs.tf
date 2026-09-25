output "ingress_routes" {
  description = "Traefik routes for modules/ingress (see its routes variable)."
  value = {
    home = {
      rule           = "Host(`home.jkandler.de`)"
      url            = "http://${kubernetes_service_v1.landing_page.metadata[0].name}:${kubernetes_service_v1.landing_page.spec[0].port[0].port}"
      forward_auth   = true
      rate_limit     = { average = 10, burst = 5 }
      max_body_bytes = 16384
    }
  }
}
