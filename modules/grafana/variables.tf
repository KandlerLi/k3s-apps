variable "grafana_admin_password" {
  description = <<-EOT
    Grafana's own admin login password. Same value as home-infra's
    monitoring_grafana_admin_password SOPS secret -- pass it via
    TF_VAR_grafana_admin_password at apply time, never given a default.
  EOT
  type        = string
  sensitive   = true
}

variable "blocky_postgres_password" {
  description = <<-EOT
    Password for the blocky-postgresql datasource's read access to
    Blocky's query-log database, reached over modules/blocky's own
    in-cluster Service now (blocky-svc:5432). Same value as
    home-infra's blocky_postgres_password SOPS secret -- pass it via
    TF_VAR_blocky_postgres_password at apply time.
  EOT
  type        = string
  sensitive   = true
}
