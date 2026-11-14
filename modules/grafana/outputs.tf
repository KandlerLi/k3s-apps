output "ingress_routes" {
  description = "Traefik routes for modules/ingress (see its routes variable)."
  value = {
    grafana = {
      rule           = "Host(`grafana.jkandler.de`)"
      url            = "http://grafana-svc.monitoring.svc.cluster.local:80"
      forward_auth   = true
      rate_limit     = { average = 120, burst = 240 }
      max_body_bytes = 1048576
    }
  }
}
