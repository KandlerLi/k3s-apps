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

# Stalwart's runtime settings, separate from the Kubernetes objects in module "stalwart".
module "stalwart_config" {
  source = "./modules/stalwart_config"

  ses_smtp_username = local.home_infra_monitoring["monitoring_ses_smtp_username"]
}

module "bulwark" {
  source = "./modules/bulwark"

  bulwark_oidc_client_secret = local.k3s_apps_bulwark["authelia_oidc_bulwark_client_secret"]
}

module "paperless" {
  source = "./modules/paperless"

  paperless_oidc_client_secret = local.k3s_apps_paperless["authelia_oidc_paperless_client_secret"]
}

module "vaultwarden" {
  source = "./modules/vaultwarden"

  # false: SSO signups closed, client API public (ADR 0028). true only while creating an account, with SSO_SIGNUPS_ALLOWED in argocd/vaultwarden.
  initial_signup = false

  authelia_oidc_client_secret = local.k3s_apps_vaultwarden["authelia_oidc_vaultwarden_client_secret"]
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

  routes = merge(
    module.home_agent.ingress_routes,
    module.open_webui.ingress_routes,
    module.grafana.ingress_routes,
    {
      home = {
        rule           = "Host(`home.jkandler.de`)"
        url            = "http://landing-page-svc:80"
        forward_auth   = true
        rate_limit     = { average = 10, burst = 5 }
        max_body_bytes = 16384
      }
      headlamp = {
        rule           = "Host(`k8s.jkandler.de`)"
        url            = "http://headlamp:80"
        forward_auth   = true
        rate_limit     = { average = 120, burst = 240 }
        max_body_bytes = 1048576
      }
      qbittorrent = {
        rule           = "Host(`torrent.jkandler.de`)"
        url            = "http://qbittorrent-web-svc:80"
        forward_auth   = true
        rate_limit     = { average = 120, burst = 240 }
        max_body_bytes = 1048576
      }
      # Argo CD's UI, deployed by k3s-bootstrap; it also logs in through Authelia's OIDC.
      argo = {
        rule           = "Host(`argo.jkandler.de`)"
        url            = "http://argocd-server.argocd.svc.cluster.local:80"
        forward_auth   = true
        rate_limit     = { average = 120, burst = 240 }
        max_body_bytes = 1048576
      }
    },
    module.authelia.ingress_routes,
    module.bulwark.ingress_routes,
    module.stalwart.ingress_routes,
    module.paperless.ingress_routes,
    module.vaultwarden.ingress_routes,
  )
}
