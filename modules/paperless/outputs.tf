output "ingress_routes" {
  description = "Traefik routes for modules/ingress (see its routes variable)."
  value = {
    # No forward_auth: the mobile app talks to the API with a token and
    # can't pass an Authelia login. Paperless authenticates every
    # request itself. /admin (Django admin, which still accepts local
    # passwords even with the regular login disabled) is left unrouted.
    docs = {
      rule           = "Host(`docs.jkandler.de`) && !PathPrefix(`/admin`)"
      url            = "http://${kubernetes_service_v1.paperless.metadata[0].name}:80"
      forward_auth   = false
      rate_limit     = { average = 120, burst = 240 }
      max_body_bytes = 104857600
    }
  }
}
