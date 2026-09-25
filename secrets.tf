# Reads the real secret values this root's own modules need directly
# from AWS Secrets Manager -- the SOPS-to-Secrets-Manager cutover
# (PARKED.md's own writeup). Replaces the ~21 TF_VAR_* variables that
# used to carry these in from either a human's own local
# export-tf-vars.sh (infra/k3s-apps' own scripts/) or CI's own GitHub
# Actions secrets (github/repo-infra's action_secrets.tf) -- both of
# those layers are gone for the secrets covered here; only the actual
# non-secret variables (home_agent_image, sankey_export_image) remain
# real root variables.
#
# One data source per Secrets Manager *group* (bootstrap/terraform-state's
# own secrets_manager.tf), not per key -- each group's value is a JSON
# blob holding several related keys, jsondecode()'d once into a local
# and indexed by key at each module call site below and in main.tf.
# Read access (github/repo-infra's aws_policies.tf) is granted to BOTH
# the apply and plan CI roles, unlike aws/dyndns's own
# apply-only-needs-the-real-value precedent -- jsondecode() at
# `terraform plan` time needs the actual value too, to compute a diff.
#
# Excludes home-infra/nextcloud (consumed by infra/home-infra's own
# Ansible only, never Terraform) and home-infra/github-runner
# (bootstrap/k3s-bootstrap's own, not this root's).

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

# A single, account-scoped GitHub PAT (read:packages on KandlerLi)
# authorizing two unrelated private packages: home-agent and
# sankey-export. See aws/secrets-manager's own k3s-apps/ghcr-pull-token
# module.
data "aws_secretsmanager_secret_version" "k3s_apps_ghcr_pull_token" {
  secret_id = "k3s-apps/ghcr-pull-token"
}

# Bulwark webmail's own Authelia OIDC client secret (plaintext half;
# home-infra/authelia holds the matching hash) -- a genuinely new
# secret, not a migration. See aws/secrets-manager's own
# k3s-apps/bulwark module.
data "aws_secretsmanager_secret_version" "k3s_apps_bulwark" {
  secret_id = "k3s-apps/bulwark"
}

# The Stalwart management-API token (an admin API key minted for
# Terraform) that provider "stalwart" authenticates with -- a genuinely
# new secret. See aws/secrets-manager's own k3s-apps/stalwart module.
data "aws_secretsmanager_secret_version" "k3s_apps_stalwart" {
  secret_id = "k3s-apps/stalwart"
}

# Paperless-ngx's own Authelia OIDC client secret (plaintext half;
# home-infra/authelia holds the matching hash). ADR 0023.
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
