# Grafana's local admin account can no longer log in by any means --
# GF_AUTH_DISABLE_LOGIN_FORM + GF_AUTH_BASIC_ENABLED=false in main.tf,
# Authelia OIDC is the only way in. So this password is inert: it isn't
# a shared secret any more (dropped from the home-infra/grafana Secrets
# Manager group 2026-09-10), just a value Grafana needs *some* file for.
# A throwaway random_password rather than a fixed placeholder, so if
# those two GF_AUTH_* switches are ever rolled back by accident there's
# still no known-value admin login. Nothing reads it; not an output.
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
  # main.tf exactly -- a Secret's data key becomes the mounted file's
  # name. Confirmed live: this was originally "admin_password" while
  # the env var pointed at .../grafana_admin_password, so the file
  # Grafana actually looked for never existed -- it started fine
  # anyway (silently falling back to the default admin/admin login)
  # instead of failing loudly, which is what made it easy to miss.
  data = {
    "grafana_admin_password" = random_password.grafana_admin.result
  }

  type = "Opaque"
}

# A real grafana.ini file, not GF_AUTH_GENERIC_OAUTH_CLIENT_SECRET__FILE
# -- confirmed live, 2026-09-08/09: that env var (the same "_FILE
# suffix" convention grafana_admin_password above uses successfully)
# left Grafana sending token_endpoint_auth_method 'none' at Authelia's
# own token endpoint instead of 'client_secret_basic', i.e. Grafana
# silently never actually read the secret -- Authelia's own logs
# showed "Client authentication failed ... determined to be used
# 'none'" on every real login attempt, and the mounted file/env var
# both checked out fine inside the running Pod, so this isn't a wiring
# mistake on this repo's own side. Matches a documented community
# finding (authelia/authelia#7203) for the exact same Grafana+Authelia
# combination: Grafana's own env-var config loader has a real gap for
# this specific nested setting (auth.generic_oauth already has an
# internal underscore, colliding with how GF_<section>_<key> parses
# section names from key names) -- the fix there was the same one
# applied here, a real grafana.ini file instead of an env var. Mounted
# at /etc/grafana/grafana.ini, the official image's own default config
# path, which layers underneath (not instead of) every other
# GF_AUTH_GENERIC_OAUTH_* env var already set in main.tf -- Grafana
# resolves each config key independently across sources, so this only
# affects client_secret specifically.
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
