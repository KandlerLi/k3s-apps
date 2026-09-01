# htpasswd-format users file, same one-line shape as home-infra's own
# templates/users.j2 -- a Secret, not a ConfigMap, since it carries a
# real password hash.
resource "kubernetes_secret_v1" "ingress_users" {
  metadata {
    name = "ingress-users"
  }

  data = {
    users = "julian:${var.shared_ingress_auth_password_hash}"
  }

  type = "Opaque"
}

# Credentials for the ACME DNS-01 challenge's own route53 provider (see
# configmap.tf's own comment on certificatesResolvers for why DNS-01
# over TLS-ALPN-01). dyndns's own traefik-acme-dns01 IAM user, scoped to
# exactly route53:ChangeResourceRecordSets/GetChange on the
# jkandler.de zone and nothing else -- see that repo's own main.tf.
resource "kubernetes_secret_v1" "ingress_acme_dns01_credentials" {
  metadata {
    name = "ingress-acme-dns01-credentials"
  }

  data = {
    AWS_ACCESS_KEY_ID     = var.k3s_ingress_acme_dns01_access_key_id
    AWS_SECRET_ACCESS_KEY = var.k3s_ingress_acme_dns01_secret_access_key
  }

  type = "Opaque"
}
