# Secret values for the modules, read from Secrets Manager at plan time.

data "aws_secretsmanager_secret_version" "home_infra_authelia" {
  secret_id = "home-infra/authelia"
}

data "aws_secretsmanager_secret_version" "home_infra_ingress" {
  secret_id = "home-infra/ingress"
}

data "aws_secretsmanager_secret_version" "home_infra_monitoring" {
  secret_id = "home-infra/monitoring"
}

data "aws_secretsmanager_secret_version" "home_infra_blocky" {
  secret_id = "home-infra/blocky"
}

# The admin API key provider "stalwart" authenticates with.
data "aws_secretsmanager_secret_version" "k3s_apps_stalwart" {
  secret_id = "k3s-apps/stalwart"
}

locals {
  home_infra_authelia   = jsondecode(data.aws_secretsmanager_secret_version.home_infra_authelia.secret_string)
  home_infra_ingress    = jsondecode(data.aws_secretsmanager_secret_version.home_infra_ingress.secret_string)
  home_infra_monitoring = jsondecode(data.aws_secretsmanager_secret_version.home_infra_monitoring.secret_string)
  home_infra_blocky     = jsondecode(data.aws_secretsmanager_secret_version.home_infra_blocky.secret_string)
  k3s_apps_stalwart     = jsondecode(data.aws_secretsmanager_secret_version.k3s_apps_stalwart.secret_string)
}
