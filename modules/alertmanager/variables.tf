variable "alertmanager_ses_smtp_username" {
  description = <<-EOT
    Sourced directly from AWS Secrets Manager's home-infra/monitoring
    group (secrets.tf's
    local.home_infra_monitoring["monitoring_ses_smtp_username"]).
  EOT
  type        = string
  sensitive   = true
}

variable "alertmanager_ses_smtp_password" {
  description = <<-EOT
    Sourced directly from AWS Secrets Manager's home-infra/monitoring
    group (secrets.tf's
    local.home_infra_monitoring["monitoring_ses_smtp_password"]).
  EOT
  type        = string
  sensitive   = true
}
