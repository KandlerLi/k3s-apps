output "ingress_routes" {
  description = "Traefik routes for modules/ingress (see its routes variable)."
  value = {
    # No forward-auth: the mobile app uses API tokens. /admin is left unrouted.
    docs = {
      rule            = "Host(`docs.jkandler.de`) && !PathPrefix(`/admin`)"
      url             = "http://${kubernetes_service_v1.paperless.metadata[0].name}:80"
      forward_auth    = false
      rate_limit      = { average = 120, burst = 240 }
      max_body_bytes  = 104857600
      referrer_policy = "same-origin"
    }
  }
}
