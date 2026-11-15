# Secret values for the modules, read from Secrets Manager at plan time.

# The admin API key provider "stalwart" authenticates with.
data "aws_secretsmanager_secret_version" "k3s_apps_stalwart" {
  secret_id = "k3s-apps/stalwart"
}

locals {
  k3s_apps_stalwart = jsondecode(data.aws_secretsmanager_secret_version.k3s_apps_stalwart.secret_string)
}
