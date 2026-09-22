# Grafana's local admin account can no longer log in by any means --
# GF_AUTH_DISABLE_LOGIN_FORM + GF_AUTH_BASIC_ENABLED=false in main.tf,
# Authelia OIDC is the only way in. So this is inert, just a value
# Grafana needs some file for -- a throwaway random_password rather
# than a fixed placeholder, so an accidental rollback of those two
# switches still has no known-value admin login.
resource "random_password" "grafana_admin" {
  length  = 40
  special = false
}

# Mounted at /run/secrets/grafana_admin_password via
# GF_SECURITY_ADMIN_PASSWORD__FILE -- same "_FILE suffix, not a raw env
# var" convention as home-infra's own Grafana deployment and this
# repo's home_agent OPENAI_API_KEY_FILE.
resource "kubernetes_secret_v1" "grafana_admin_password" {
  metadata {
    name = "grafana-admin-password"
  }

  # Key name must match the GF_SECURITY_ADMIN_PASSWORD__FILE path in
  # main.tf exactly -- a mismatch here fails silently (falls back to
  # the default admin/admin login) rather than erroring.
  data = {
    "grafana_admin_password" = random_password.grafana_admin.result
  }

  type = "Opaque"
}

# A real grafana.ini file, not GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET__FILE
# -- that env var silently never gets read (Grafana's own env-var
# loader gap, authelia/authelia#7203). Mounted at
# /etc/grafana/grafana.ini, layering underneath every other
# GF_AUTH_GENERIC_OAUTH_* env var in main.tf -- Grafana resolves each
# config key independently, so this only affects client_secret. See
# current-state.md.
resource "kubernetes_secret_v1" "grafana_oidc_client_secret" {
  metadata {
    name = "grafana-oidc-client-secret"
  }

  data = {
    "grafana.ini" = <<-EOT
      [auth.generic_oauth]
      client_secret = ${var.authelia_oidc_grafana_client_secret}
    EOT
  }

  type = "Opaque"
}

# A Secret, not a ConfigMap, because the rendered file carries
# blocky_postgres_password in plaintext -- matching home-infra's own
# no_log: true on the equivalent Ansible task. Grafana just reads every
# YAML file under provisioning/datasources, so the mount looks
# identical to it either way.
resource "kubernetes_secret_v1" "grafana_datasources" {
  metadata {
    name = "grafana-datasources"
  }

  data = {
    "datasources.yaml" = templatefile("${path.module}/templates/datasources.yaml.tftpl", {
      blocky_postgres_password = var.blocky_postgres_password
    })
  }

  type = "Opaque"
}
