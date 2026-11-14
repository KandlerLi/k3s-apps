output "ingress_routes" {
  description = "Traefik routes for modules/ingress (see its routes variable)."
  value = {
    # The apps can't pass forward-auth, so their API is public once initial_signup is off (ADR 0028).
    vaultwarden-api = {
      rule           = "Host(`vault.jkandler.de`) && (PathPrefix(`/api/`) || PathPrefix(`/identity/`) || PathPrefix(`/notifications/hub`))"
      priority       = 20
      url            = "http://vaultwarden-svc:80"
      forward_auth   = var.initial_signup
      rate_limit     = { average = 120, burst = 240 }
      max_body_bytes = 20971520
    }
    # Web vault behind Authelia; /admin is left unrouted.
    vaultwarden = {
      rule           = "Host(`vault.jkandler.de`) && !PathPrefix(`/admin`)"
      priority       = 10
      url            = "http://vaultwarden-svc:80"
      forward_auth   = true
      rate_limit     = { average = 120, burst = 240 }
      max_body_bytes = 20971520
    }
  }
}
