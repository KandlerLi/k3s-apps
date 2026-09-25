output "ingress_routes" {
  description = "Traefik routes for modules/ingress (see its routes variable)."
  value = {
    deluge = {
      rule           = "Host(`torrent.jkandler.de`)"
      url            = "http://${kubernetes_service_v1.deluge_web.metadata[0].name}:${kubernetes_service_v1.deluge_web.spec[0].port[0].port}"
      forward_auth   = true
      rate_limit     = { average = 120, burst = 240 }
      max_body_bytes = 1048576
    }
  }
}
