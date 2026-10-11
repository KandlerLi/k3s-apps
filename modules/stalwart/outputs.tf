locals {
  stalwart_url = "http://${kubernetes_service_v1.stalwart_internal.metadata[0].name}:${kubernetes_service_v1.stalwart_internal.spec[0].port[0].port}"
}

output "ingress_routes" {
  description = "Traefik routes for modules/ingress (see its routes variable)."
  value = {
    # Protocol endpoints skip Authelia: clients can't follow a login redirect, and Stalwart authenticates each.
    stalwart-api = {
      rule         = "Host(`stalwart.jkandler.de`) && (PathPrefix(`/jmap`) || PathPrefix(`/.well-known`) || PathPrefix(`/dav`) || PathPrefix(`/auth`) || PathPrefix(`/mail/config-v1.1.xml`) || PathPrefix(`/autodiscover`))"
      priority     = 100
      url          = local.stalwart_url
      forward_auth = false
      rate_limit   = { average = 600, burst = 1200 }
    }
    # Everything else is gated by Authelia first, then Stalwart's login.
    stalwart = {
      rule         = "Host(`stalwart.jkandler.de`)"
      priority     = 10
      url          = local.stalwart_url
      forward_auth = true
      rate_limit   = { average = 120, burst = 240 }
    }
  }
}
