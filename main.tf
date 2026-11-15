# Root module: one module block per service under modules/. See the README.

# Argo CD deploys these from argocd/ now: see README, "Argo CD".
removed {
  from = module.landing_page

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.headlamp

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.qbittorrent

  lifecycle {
    destroy = false
  }
}

module "home_agent" {
  source = "./modules/home_agent"
}

module "open_webui" {
  source = "./modules/open_webui"

  depends_on = [module.home_agent]
}

module "sankey_export" {
  source = "./modules/sankey_export"
}

# kube-state-metrics moved to argocd/kube-state-metrics, the node-exporter DaemonSet to k3s-bootstrap.
removed {
  from = module.node_exporter

  lifecycle {
    destroy = false
  }
}

module "grafana" {
  source = "./modules/grafana"

  blocky_postgres_password            = local.home_infra_blocky["blocky_postgres_password"]
  authelia_oidc_grafana_client_secret = local.home_infra_grafana["authelia_oidc_grafana_client_secret"]

  # Grafana's datasource names blocky-svc by string, so the ordering is explicit.
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

# Stalwart's runtime settings moved to the stalwart-config repo, which imported them.
removed {
  from = module.stalwart_config

  lifecycle {
    destroy = false
  }
}

module "bulwark" {
  source = "./modules/bulwark"
}

module "paperless" {
  source = "./modules/paperless"

  paperless_oidc_client_secret = local.k3s_apps_paperless["authelia_oidc_paperless_client_secret"]
}

module "vaultwarden" {
  source = "./modules/vaultwarden"
}

module "authelia" {
  source = "./modules/authelia"

  authelia_session_secret                      = local.home_infra_authelia["authelia_session_secret"]
  authelia_storage_encryption_key              = local.home_infra_authelia["authelia_storage_encryption_key"]
  authelia_reset_password_jwt_secret           = local.home_infra_authelia["authelia_reset_password_jwt_secret"]
  authelia_admin_password_hash                 = local.home_infra_authelia["authelia_admin_password_hash"]
  authelia_stalwart_admin_password_hash        = local.home_infra_authelia["authelia_stalwart_admin_password_hash"]
  alertmanager_ses_smtp_username               = local.home_infra_monitoring["monitoring_ses_smtp_username"]
  alertmanager_ses_smtp_password               = local.home_infra_monitoring["monitoring_ses_smtp_password"]
  authelia_oidc_hmac_secret                    = local.home_infra_authelia["authelia_oidc_hmac_secret"]
  authelia_oidc_issuer_private_key             = local.home_infra_authelia["authelia_oidc_issuer_private_key"]
  authelia_oidc_grafana_client_secret_hash     = local.home_infra_authelia["authelia_oidc_grafana_client_secret_hash"]
  authelia_oidc_openwebui_client_secret_hash   = local.home_infra_authelia["authelia_oidc_openwebui_client_secret_hash"]
  authelia_oidc_nextcloud_client_secret_hash   = local.home_infra_authelia["authelia_oidc_nextcloud_client_secret_hash"]
  authelia_oidc_bulwark_client_secret_hash     = local.home_infra_authelia["authelia_oidc_bulwark_client_secret_hash"]
  authelia_oidc_paperless_client_secret_hash   = local.home_infra_authelia["authelia_oidc_paperless_client_secret_hash"]
  authelia_oidc_vaultwarden_client_secret_hash = local.home_infra_authelia["authelia_oidc_vaultwarden_client_secret_hash"]
  authelia_oidc_argocd_client_secret_hash      = local.home_infra_authelia["authelia_oidc_argocd_client_secret_hash"]
}

module "ingress" {
  source = "./modules/ingress"

  k3s_ingress_acme_dns01_access_key_id     = local.home_infra_ingress["k3s_ingress_acme_dns01_access_key_id"]
  k3s_ingress_acme_dns01_secret_access_key = local.home_infra_ingress["k3s_ingress_acme_dns01_secret_access_key"]
}
