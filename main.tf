# Root module: wires the two workload modules together. Each module is
# self-contained (its own resources, its own files/ where relevant) so a
# third service can be added the same way -- a new modules/<service>/
# directory plus a module block here -- without touching an existing
# one's code.

module "landing_page" {
  source = "./modules/landing_page"
}

module "deluge" {
  source = "./modules/deluge"

  deluge_web_password = var.deluge_web_password
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

module "grafana" {
  source = "./modules/grafana"

  grafana_admin_password   = var.grafana_admin_password
  blocky_postgres_password = var.blocky_postgres_password
}

module "alertmanager" {
  source = "./modules/alertmanager"

  alertmanager_ses_smtp_username = var.alertmanager_ses_smtp_username
  alertmanager_ses_smtp_password = var.alertmanager_ses_smtp_password
}

module "github_runner" {
  source = "./modules/github_runner"

  github_runner_github_token = var.github_runner_github_token
  github_runner_repositories = var.github_runner_repositories
}
