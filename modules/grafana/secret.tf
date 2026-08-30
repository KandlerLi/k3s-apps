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
    "grafana_admin_password" = var.grafana_admin_password
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
