# Inert: local login is disabled, Authelia OIDC is the only way in.
resource "random_password" "grafana_admin" {
  length  = 40
  special = false
}

# Mounted via GF_SECURITY_ADMIN_PASSWORD__FILE.
resource "kubernetes_secret_v1" "grafana_admin_password" {
  metadata {
    name      = "grafana-admin-password"
    namespace = "monitoring"
  }

  # Must match the __FILE path exactly, or Grafana silently falls back to admin/admin.
  data = {
    "grafana_admin_password" = random_password.grafana_admin.result
  }

  type = "Opaque"
}

# A real grafana.ini: GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET__FILE is never read (authelia/authelia#7203).
resource "kubernetes_secret_v1" "grafana_oidc_client_secret" {
  metadata {
    name      = "grafana-oidc-client-secret"
    namespace = "monitoring"
  }

  data = {
    "grafana.ini" = <<-EOT
      [auth.generic_oauth]
      client_secret = ${var.authelia_oidc_grafana_client_secret}
    EOT
  }

  type = "Opaque"
}

# A Secret: the rendered file carries the Postgres password.
resource "kubernetes_secret_v1" "grafana_datasources" {
  metadata {
    name      = "grafana-datasources"
    namespace = "monitoring"
  }

  data = {
    "datasources.yaml" = templatefile("${path.module}/templates/datasources.yaml.tftpl", {
      blocky_postgres_password = var.blocky_postgres_password
    })
  }

  type = "Opaque"
}
