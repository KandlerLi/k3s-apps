# Root module: wires this cluster's own workload modules together. Each
# module is self-contained so a new one can be added the same way -- a
# new modules/<service>/ directory plus a module block here -- without
# touching an existing one's code. CI applies this root on every merge
# to main; the PR review is the only gate. The self-hosted runner
# itself and the cluster-scoped PVs this root's own PVCs bind to live
# in the separate, local-only k3s-bootstrap repo instead.

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
  home_agent_ghcr_token        = local.k3s_apps_ghcr_pull_token["token"]
  home_agent_openai_api_key    = local.home_infra_home_agent["home_agent_openai_api_key"]
  home_agent_anthropic_api_key = local.home_infra_home_agent["home_agent_anthropic_api_key"]
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
  sankey_export_ghcr_token   = local.k3s_apps_ghcr_pull_token["token"]
  sankey_export_app_password = local.k3s_apps_sankey_export["sankey_export_app_password"]
}

module "node_exporter" {
  source = "./modules/node_exporter"
}

module "grafana" {
  source = "./modules/grafana"

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

module "stalwart" {
  source = "./modules/stalwart"

  stalwart_ses_smtp_username = local.home_infra_monitoring["monitoring_ses_smtp_username"]
  stalwart_ses_smtp_password = local.home_infra_monitoring["monitoring_ses_smtp_password"]
}

# Stalwart's own runtime settings (CORS, IP allow-list, ...), adopted from
# what was originally set by hand in its admin UI. Separate from
# module "stalwart" above, which owns the Kubernetes objects.
module "stalwart_config" {
  source = "./modules/stalwart_config"

  ses_smtp_username = local.home_infra_monitoring["monitoring_ses_smtp_username"]
}

module "bulwark" {
  source = "./modules/bulwark"

  bulwark_oidc_client_secret = local.k3s_apps_bulwark["authelia_oidc_bulwark_client_secret"]
}

module "authelia" {
  source = "./modules/authelia"

  authelia_session_secret                    = local.home_infra_authelia["authelia_session_secret"]
  authelia_storage_encryption_key            = local.home_infra_authelia["authelia_storage_encryption_key"]
  authelia_reset_password_jwt_secret         = local.home_infra_authelia["authelia_reset_password_jwt_secret"]
  authelia_admin_password_hash               = local.home_infra_authelia["authelia_admin_password_hash"]
  authelia_stalwart_admin_password_hash      = local.home_infra_authelia["authelia_stalwart_admin_password_hash"]
  alertmanager_ses_smtp_username             = local.home_infra_monitoring["monitoring_ses_smtp_username"]
  alertmanager_ses_smtp_password             = local.home_infra_monitoring["monitoring_ses_smtp_password"]
  authelia_oidc_hmac_secret                  = local.home_infra_authelia["authelia_oidc_hmac_secret"]
  authelia_oidc_issuer_private_key           = local.home_infra_authelia["authelia_oidc_issuer_private_key"]
  authelia_oidc_grafana_client_secret_hash   = local.home_infra_authelia["authelia_oidc_grafana_client_secret_hash"]
  authelia_oidc_openwebui_client_secret_hash = local.home_infra_authelia["authelia_oidc_openwebui_client_secret_hash"]
  authelia_oidc_nextcloud_client_secret_hash = local.home_infra_authelia["authelia_oidc_nextcloud_client_secret_hash"]
  authelia_oidc_bulwark_client_secret_hash   = local.home_infra_authelia["authelia_oidc_bulwark_client_secret_hash"]
}

module "ingress" {
  source = "./modules/ingress"

  k3s_ingress_acme_dns01_access_key_id     = local.home_infra_ingress["k3s_ingress_acme_dns01_access_key_id"]
  k3s_ingress_acme_dns01_secret_access_key = local.home_infra_ingress["k3s_ingress_acme_dns01_secret_access_key"]

  routes = merge(
    module.home_agent.ingress_routes,
    module.open_webui.ingress_routes,
    module.deluge.ingress_routes,
    module.grafana.ingress_routes,
    module.landing_page.ingress_routes,
    module.kubernetes_dashboard.ingress_routes,
    module.authelia.ingress_routes,
    module.bulwark.ingress_routes,
    module.stalwart.ingress_routes,
  )
}
