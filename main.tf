# Root module: wires this cluster's own workload modules together. Each
# module is self-contained (its own resources, its own files/ where
# relevant) so a new one can be added the same way -- a new
# modules/<service>/ directory plus a module block here -- without
# touching an existing one's code. This root is now CI-applied (see
# .github/workflows/), gated on the production environment's reviewer
# approval before a real apply runs. The self-hosted runner itself and
# the cluster-scoped PVs this root's own PVCs bind to live in the
# separate, local-only k3s-bootstrap repo instead -- originally a
# bootstrap/ subdirectory of this same repo, extracted into its own
# standalone repo alongside terraform-state (2026-09-03; repo-infra
# was there too at the time, since moved to its own github/ directory
# on 2026-09-05).

module "landing_page" {
  source = "./modules/landing_page"
}

module "kubernetes_dashboard" {
  source = "./modules/kubernetes_dashboard"
}

module "deluge" {
  source = "./modules/deluge"
}

module "home_agent" {
  source = "./modules/home_agent"

  home_agent_image             = var.home_agent_image
  home_agent_ghcr_token        = var.home_agent_ghcr_token
  home_agent_openai_api_key    = var.home_agent_openai_api_key
  nextcloud_tools_app_password = var.nextcloud_tools_app_password
}

module "open_webui" {
  source = "./modules/open_webui"

  depends_on = [module.home_agent]
}

module "sankey_export" {
  source = "./modules/sankey_export"

  sankey_export_image        = var.sankey_export_image
  sankey_export_ghcr_token   = var.home_agent_ghcr_token
  sankey_export_app_password = var.sankey_export_app_password
}

module "grafana" {
  source = "./modules/grafana"

  grafana_admin_password   = var.grafana_admin_password
  blocky_postgres_password = var.blocky_postgres_password

  # blocky-svc:5432, referenced as a plain string in this module's own
  # datasources.yaml.tftpl (same convention modules/ingress's own
  # dynamic.yml.j2 uses for every backend it routes to), not a live
  # Terraform reference -- explicit here since nothing else would
  # infer the ordering.
  depends_on = [module.blocky]
}

module "alertmanager" {
  source = "./modules/alertmanager"

  alertmanager_ses_smtp_username = var.alertmanager_ses_smtp_username
  alertmanager_ses_smtp_password = var.alertmanager_ses_smtp_password
}

module "blocky" {
  source = "./modules/blocky"

  blocky_postgres_password = var.blocky_postgres_password
}

module "authelia" {
  source = "./modules/authelia"

  authelia_session_secret            = var.authelia_session_secret
  authelia_storage_encryption_key    = var.authelia_storage_encryption_key
  authelia_reset_password_jwt_secret = var.authelia_reset_password_jwt_secret
  authelia_admin_password_hash       = var.authelia_admin_password_hash
  alertmanager_ses_smtp_username     = var.alertmanager_ses_smtp_username
  alertmanager_ses_smtp_password     = var.alertmanager_ses_smtp_password
}

module "ingress" {
  source = "./modules/ingress"

  shared_ingress_auth_password_hash        = var.shared_ingress_auth_password_hash
  k3s_ingress_acme_dns01_access_key_id     = var.k3s_ingress_acme_dns01_access_key_id
  k3s_ingress_acme_dns01_secret_access_key = var.k3s_ingress_acme_dns01_secret_access_key

  # Every backend it routes to by Service name -- a plain string
  # inside a ConfigMap's own YAML content, not a real Terraform
  # reference, so this has to be explicit rather than inferred.
  depends_on = [
    module.landing_page,
    module.kubernetes_dashboard,
    module.deluge,
    module.home_agent,
    module.open_webui,
    module.grafana,
    module.authelia,
  ]
}
