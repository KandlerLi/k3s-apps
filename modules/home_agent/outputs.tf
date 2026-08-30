# Exposed so the root module can wire ai.jkandler.de's combined Ingress
# (see ai_ingress.tf) without reaching into this module's own resources
# directly -- Terraform has no other way to reference another module's
# resource from outside it.

output "service_name" {
  value = kubernetes_service_v1.home_agent.metadata[0].name
}
