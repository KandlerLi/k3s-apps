output "ingress_routes" {
  description = "Traefik routes for modules/ingress (see its routes variable)."
  value = {
    # No body-size limit (attachments); Bulwark calls Stalwart's JMAP from the browser, so Stalwart needs CORS for this origin.
    mail = {
      rule         = "Host(`mail.jkandler.de`)"
      url          = "http://bulwark-svc:80"
      forward_auth = true
      rate_limit   = { average = 120, burst = 240 }
    }
  }
}
