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
