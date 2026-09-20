variable "stalwart_ses_smtp_username" {
  description = <<-EOT
    Sourced from AWS Secrets Manager's home-infra/monitoring group
    (secrets.tf's local.home_infra_monitoring["monitoring_ses_smtp_username"])
    -- the same SES SMTP credential aws/ses-relay's IAM policy scopes to
    the whole jkandler.de domain identity, already reused by Alertmanager
    and Authelia. Not sensitive on its own (it's an IAM access key ID,
    not a secret), but kept alongside the password so both live in one
    place.
  EOT
  type        = string
}

variable "stalwart_ses_smtp_password" {
  description = <<-EOT
    Sourced from AWS Secrets Manager's home-infra/monitoring group
    (secrets.tf's local.home_infra_monitoring["monitoring_ses_smtp_password"]).
    This is the *derived* SES SMTP password (aws/ses-relay's README:
    "Deriving the SMTP password"), not the raw IAM secret access key.
  EOT
  type        = string
  sensitive   = true
}
