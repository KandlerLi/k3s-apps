# Credentials for the ACME DNS-01 route53 provider (dyndns's traefik-acme-dns01 user).
resource "kubernetes_secret_v1" "ingress_acme_dns01_credentials" {
  metadata {
    namespace = "apps"
    name      = "ingress-acme-dns01-credentials"
  }

  data = {
    AWS_ACCESS_KEY_ID     = var.k3s_ingress_acme_dns01_access_key_id
    AWS_SECRET_ACCESS_KEY = var.k3s_ingress_acme_dns01_secret_access_key
  }

  type = "Opaque"
}
