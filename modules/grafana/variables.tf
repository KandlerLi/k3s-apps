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
    Blocky's query-log database, reached over the additive
    192.168.101.1:5432 listener home-infra's blocky role now exposes
    (see that role's blocky_postgres_k3s_bind_address). Same value as
    home-infra's blocky_postgres_password SOPS secret -- pass it via
    TF_VAR_blocky_postgres_password at apply time.
  EOT
  type        = string
  sensitive   = true
}
