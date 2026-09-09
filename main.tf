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
  home_agent_ghcr_token        = local.home_infra_home_agent["home_agent_ghcr_token"]
  home_agent_openai_api_key    = local.home_infra_home_agent["home_agent_openai_api_key"]
  nextcloud_tools_app_password = local.home_infra_home_agent["nextcloud_tools_app_password"]
}

module "open_webui" {
  source = "./modules/open_webui"

  authelia_oidc_openwebui_client_secret = local.home_infra_open_webui["authelia_oidc_openwebui_client_secret"]

  depends_on = [module.home_agent]
}

module "sankey_export" {
  source = "./modules/sankey_export"

  sankey_export_image        = var.sankey_export_image
  sankey_export_ghcr_token   = local.home_infra_home_agent["home_agent_ghcr_token"]
  sankey_export_app_password = local.k3s_apps_sankey_export["sankey_export_app_password"]
}

module "grafana" {
  source = "./modules/grafana"

  grafana_admin_password              = local.home_infra_grafana["monitoring_grafana_admin_password"]
  blocky_postgres_password            = local.home_infra_blocky["blocky_postgres_password"]
  authelia_oidc_grafana_client_secret = local.home_infra_grafana["authelia_oidc_grafana_client_secret"]

  # blocky-svc:5432, referenced as a plain string in this module's own
  # datasources.yaml.tftpl (same convention modules/ingress's own
  # dynamic.yml.j2 uses for every backend it routes to), not a live
  # Terraform reference -- explicit here since nothing else would
  # infer the ordering.
  depends_on = [module.blocky]
}

module "alertmanager" {
  source = "./modules/alertmanager"

  alertmanager_ses_smtp_username = local.home_infra_monitoring["monitoring_ses_smtp_username"]
  alertmanager_ses_smtp_password = local.home_infra_monitoring["monitoring_ses_smtp_password"]
}

module "blocky" {
  source = "./modules/blocky"

  blocky_postgres_password = local.home_infra_blocky["blocky_postgres_password"]
}

module "authelia" {
  source = "./modules/authelia"

  authelia_session_secret                    = local.home_infra_authelia["authelia_session_secret"]
  authelia_storage_encryption_key            = local.home_infra_authelia["authelia_storage_encryption_key"]
  authelia_reset_password_jwt_secret         = local.home_infra_authelia["authelia_reset_password_jwt_secret"]
  authelia_admin_password_hash               = local.home_infra_authelia["authelia_admin_password_hash"]
  alertmanager_ses_smtp_username             = local.home_infra_monitoring["monitoring_ses_smtp_username"]
  alertmanager_ses_smtp_password             = local.home_infra_monitoring["monitoring_ses_smtp_password"]
  authelia_oidc_hmac_secret                  = local.home_infra_authelia["authelia_oidc_hmac_secret"]
  authelia_oidc_issuer_private_key           = local.home_infra_authelia["authelia_oidc_issuer_private_key"]
  authelia_oidc_grafana_client_secret_hash   = local.home_infra_authelia["authelia_oidc_grafana_client_secret_hash"]
  authelia_oidc_openwebui_client_secret_hash = local.home_infra_authelia["authelia_oidc_openwebui_client_secret_hash"]
  authelia_oidc_nextcloud_client_secret_hash = local.home_infra_authelia["authelia_oidc_nextcloud_client_secret_hash"]
}

module "ingress" {
  source = "./modules/ingress"

  shared_ingress_auth_password_hash        = local.home_infra_ingress["shared_ingress_auth_password_hash"]
  k3s_ingress_acme_dns01_access_key_id     = local.home_infra_ingress["k3s_ingress_acme_dns01_access_key_id"]
  k3s_ingress_acme_dns01_secret_access_key = local.home_infra_ingress["k3s_ingress_acme_dns01_secret_access_key"]

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
