output "ingress_routes" {
  description = "Traefik routes for modules/ingress (see its routes variable)."
  value = {
    grafana = {
      rule           = "Host(`grafana.jkandler.de`)"
      url            = "http://${kubernetes_service_v1.grafana.metadata[0].name}:${kubernetes_service_v1.grafana.spec[0].port[0].port}"
      forward_auth   = true
      rate_limit     = { average = 120, burst = 240 }
      max_body_bytes = 1048576
    }
  }
}
