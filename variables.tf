variable "deluge_web_password" {
  description = <<-EOT
    Deluge's own web UI login password (separate from the shared
    Traefik Basic Auth in front of everything -- Deluge cannot disable
    its own login, per home-infra's deluge role). Same value as
    home-infra's deluge_web_password SOPS secret.

    Never given a default and never written to a file in this repo --
    pass it via the TF_VAR_deluge_web_password environment variable at
    apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "home_agent_image" {
  description = <<-EOT
    Full ghcr.io/kandlerli/home-agent reference, pinned by digest. See
    modules/home_agent's own variable of the same name.
  EOT
  type        = string
}

variable "home_agent_ghcr_token" {
  description = <<-EOT
    Read-scoped GitHub PAT for pulling ghcr.io/kandlerli/home-agent.
    Same value as home-infra's home_agent_ghcr_token SOPS secret --
    pass it via TF_VAR_home_agent_ghcr_token at apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "home_agent_openai_api_key" {
  description = <<-EOT
    Same value as home-infra's home_agent_openai_api_key SOPS secret.
    Pass via TF_VAR_home_agent_openai_api_key at apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "nextcloud_tools_app_password" {
  description = <<-EOT
    A Nextcloud app password dedicated to this k3s copy of
    nextcloud_tools, independently revocable from home-infra's own copy
    -- see modules/home_agent's own variable of the same name for how
    it was generated. Pass via TF_VAR_nextcloud_tools_app_password at
    apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "grafana_admin_password" {
  description = <<-EOT
    Same value as home-infra's monitoring_grafana_admin_password SOPS
    secret. Pass via TF_VAR_grafana_admin_password at apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "blocky_postgres_password" {
  description = <<-EOT
    Same value as home-infra's blocky_postgres_password SOPS secret --
    used by both Grafana's blocky-postgresql datasource and
    modules/blocky's own Postgres instance (the same database, now
    that Blocky itself also runs in the cluster). Pass via
    TF_VAR_blocky_postgres_password at apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "alertmanager_ses_smtp_username" {
  description = <<-EOT
    Same value as home-infra's monitoring_ses_smtp_username SOPS
    secret. Pass via TF_VAR_alertmanager_ses_smtp_username at apply
    time.
  EOT
  type        = string
  sensitive   = true
}

variable "alertmanager_ses_smtp_password" {
  description = <<-EOT
    Same value as home-infra's monitoring_ses_smtp_password SOPS
    secret. Pass via TF_VAR_alertmanager_ses_smtp_password at apply
    time.
  EOT
  type        = string
  sensitive   = true
}

variable "github_runner_github_token" {
  description = <<-EOT
    Same value as home-infra's github_runner_github_token SOPS secret
    (the VM-based role's own PAT). See modules/github_runner's own
    variable of the same name. Pass via TF_VAR_github_runner_github_token
    at apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "github_runner_repositories" {
  description = <<-EOT
    Loaded from this repo's own repositories.auto.tfvars.json
    (Terraform auto-loads it) -- see modules/github_runner's own
    variable of the same name for where that file comes from. No
    default here: if that file is ever missing, this should fail loudly
    rather than silently apply zero runners.
  EOT
  type = list(object({
    id         = string
    repository = string
  }))
}

variable "shared_ingress_auth_password_hash" {
  description = <<-EOT
    Same bcrypt hash as home-infra's shared_ingress_auth_password_hash
    SOPS secret. See modules/ingress's own variable of the same name.
    Pass via TF_VAR_shared_ingress_auth_password_hash at apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "k3s_ingress_acme_dns01_access_key_id" {
  description = <<-EOT
    Same value as home-infra's k3s_ingress_acme_dns01_access_key_id
    SOPS secret. See modules/ingress's own variable of the same name.
    Pass via TF_VAR_k3s_ingress_acme_dns01_access_key_id at apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "k3s_ingress_acme_dns01_secret_access_key" {
  description = <<-EOT
    Same value as home-infra's k3s_ingress_acme_dns01_secret_access_key
    SOPS secret. See modules/ingress's own variable of the same name.
    Pass via TF_VAR_k3s_ingress_acme_dns01_secret_access_key at apply
    time.
  EOT
  type        = string
  sensitive   = true
}
