output "ingress_routes" {
  description = "Traefik routes for modules/ingress (see its routes variable)."
  value = {
    # No body-size limit: webmail uploads attachments. Bulwark calls
    # Stalwart's JMAP endpoint straight from the browser, so Stalwart
    # needs CORS for this origin.
    mail = {
      rule         = "Host(`mail.jkandler.de`)"
      url          = "http://${kubernetes_service_v1.bulwark.metadata[0].name}:${kubernetes_service_v1.bulwark.spec[0].port[0].port}"
      forward_auth = true
      rate_limit   = { average = 120, burst = 240 }
    }
  }
}
