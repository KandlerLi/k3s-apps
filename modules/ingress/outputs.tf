output "cluster_ip" {
  description = "ingress-svc's ClusterIP, for Pods that pin a public hostname to Traefik in-cluster instead of hairpinning through the router."
  value       = kubernetes_service_v1.ingress.spec[0].cluster_ip
}
