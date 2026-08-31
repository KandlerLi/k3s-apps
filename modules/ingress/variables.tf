variable "shared_ingress_auth_password_hash" {
  description = <<-EOT
    Same bcrypt hash as home-infra's shared_ingress_auth_password_hash
    SOPS secret -- the one shared Basic Auth credential gating
    deluge/grafana/home/the agent API (Open WebUI and Nextcloud have
    their own separate logins instead). Pass via
    TF_VAR_shared_ingress_auth_password_hash at apply time.
  EOT
  type        = string
  sensitive   = true
}
