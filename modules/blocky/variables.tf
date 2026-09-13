variable "blocky_postgres_password" {
  description = <<-EOT
    Sourced directly from AWS Secrets Manager's home-infra/blocky
    group (secrets.tf's
    local.home_infra_blocky["blocky_postgres_password"]). Embedded
    directly in Blocky's own config.yml (queryLog.target), which is
    why that config lives in a Secret, not a ConfigMap -- see
    secret.tf's own comment.
  EOT
  type        = string
  sensitive   = true
}
