output "ingress_routes" {
  description = "Traefik routes for modules/ingress (see its routes variable)."
  value = {
    # No forward-auth: this is the login portal itself, and Authelia's
    # own access_control already marks this hostname bypass.
    auth = {
      rule         = "Host(`auth.jkandler.de`)"
      url          = "http://${kubernetes_service_v1.authelia.metadata[0].name}:${kubernetes_service_v1.authelia.spec[0].port[0].port}"
      forward_auth = false
    }
  }
}
