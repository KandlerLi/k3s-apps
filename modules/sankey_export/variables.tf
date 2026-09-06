variable "sankey_export_image" {
  description = <<-EOT
    Full ghcr.io/kandlerli/sankey-export reference, pinned by digest.
    Built by home-infra's build-sankey-export.yml workflow.
  EOT
  type        = string
}

variable "sankey_export_ghcr_token" {
  description = <<-EOT
    Same read-scoped GHCR PAT as home_agent's own ghcr_token variable
    (see modules/home_agent's own variable of the same purpose) --
    this is a private package under the same GitHub account, not a
    separately issued credential.
  EOT
  type        = string
  sensitive   = true
}

variable "sankey_export_app_password" {
  description = <<-EOT
    The existing sankey-export Nextcloud account's app password, reused
    as-is from home-infra's own copy rather than a newly bootstrapped
    account -- the home-infra systemd deployment is being fully retired
    once this CronJob is confirmed live, not run alongside it
    long-term, so there's no "independently revocable from a parallel
    copy" concern the way nextcloud_tools_app_password has. Pass via
    TF_VAR_sankey_export_app_password at apply time.
  EOT
  type        = string
  sensitive   = true
}
