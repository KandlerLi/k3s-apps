variable "blocky_postgres_password" {
  description = <<-EOT
    Same value as home-infra's blocky_postgres_password SOPS secret.
    Embedded directly in Blocky's own config.yml (queryLog.target),
    which is why that config lives in a Secret, not a ConfigMap -- see
    secret.tf's own comment. Pass via TF_VAR_blocky_postgres_password
    at apply time.
  EOT
  type        = string
  sensitive   = true
}
