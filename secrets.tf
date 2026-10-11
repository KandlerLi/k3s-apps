# Secret values for the modules, read from Secrets Manager at plan time.

data "aws_secretsmanager_secret_version" "home_infra_authelia" {
  secret_id = "home-infra/authelia"
}

data "aws_secretsmanager_secret_version" "home_infra_grafana" {
  secret_id = "home-infra/grafana"
}

data "aws_secretsmanager_secret_version" "home_infra_open_webui" {
  secret_id = "home-infra/open-webui"
}

data "aws_secretsmanager_secret_version" "home_infra_ingress" {
  secret_id = "home-infra/ingress"
}

data "aws_secretsmanager_secret_version" "home_infra_home_agent" {
  secret_id = "home-infra/home-agent"
}

data "aws_secretsmanager_secret_version" "home_infra_monitoring" {
  secret_id = "home-infra/monitoring"
}

data "aws_secretsmanager_secret_version" "home_infra_blocky" {
  secret_id = "home-infra/blocky"
}

data "aws_secretsmanager_secret_version" "k3s_apps_sankey_export" {
  secret_id = "k3s-apps/sankey-export"
}

# One account-scoped GHCR pull token for both private images.
data "aws_secretsmanager_secret_version" "k3s_apps_ghcr_pull_token" {
  secret_id = "k3s-apps/ghcr-pull-token"
}

# Bulwark's Authelia OIDC client secret (plaintext half).
data "aws_secretsmanager_secret_version" "k3s_apps_bulwark" {
  secret_id = "k3s-apps/bulwark"
}

# The admin API key provider "stalwart" authenticates with.
data "aws_secretsmanager_secret_version" "k3s_apps_stalwart" {
  secret_id = "k3s-apps/stalwart"
}

# Paperless-ngx's Authelia OIDC client secret (plaintext half), ADR 0023.
data "aws_secretsmanager_secret_version" "k3s_apps_paperless" {
  secret_id = "k3s-apps/paperless"
}

locals {
  home_infra_authelia      = jsondecode(data.aws_secretsmanager_secret_version.home_infra_authelia.secret_string)
  home_infra_grafana       = jsondecode(data.aws_secretsmanager_secret_version.home_infra_grafana.secret_string)
  home_infra_open_webui    = jsondecode(data.aws_secretsmanager_secret_version.home_infra_open_webui.secret_string)
  home_infra_ingress       = jsondecode(data.aws_secretsmanager_secret_version.home_infra_ingress.secret_string)
  home_infra_home_agent    = jsondecode(data.aws_secretsmanager_secret_version.home_infra_home_agent.secret_string)
  home_infra_monitoring    = jsondecode(data.aws_secretsmanager_secret_version.home_infra_monitoring.secret_string)
  home_infra_blocky        = jsondecode(data.aws_secretsmanager_secret_version.home_infra_blocky.secret_string)
  k3s_apps_sankey_export   = jsondecode(data.aws_secretsmanager_secret_version.k3s_apps_sankey_export.secret_string)
  k3s_apps_ghcr_pull_token = jsondecode(data.aws_secretsmanager_secret_version.k3s_apps_ghcr_pull_token.secret_string)
  k3s_apps_bulwark         = jsondecode(data.aws_secretsmanager_secret_version.k3s_apps_bulwark.secret_string)
  k3s_apps_stalwart        = jsondecode(data.aws_secretsmanager_secret_version.k3s_apps_stalwart.secret_string)
  k3s_apps_paperless       = jsondecode(data.aws_secretsmanager_secret_version.k3s_apps_paperless.secret_string)
}
