# Same reasoning as home_agent's own outputs.tf -- lets the root
# module's ai_ingress.tf reference this Service without reaching into
# this module's resources directly.

output "service_name" {
  value = kubernetes_service_v1.open_webui.metadata[0].name
}
