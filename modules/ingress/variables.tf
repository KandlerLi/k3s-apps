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

variable "k3s_ingress_acme_dns01_access_key_id" {
  description = <<-EOT
    IAM access key ID for the ACME DNS-01 challenge's own route53
    provider -- dyndns's own traefik-acme-dns01 IAM user output. Same
    value as home-infra's k3s_ingress_acme_dns01_access_key_id SOPS
    secret. Pass via TF_VAR_k3s_ingress_acme_dns01_access_key_id at
    apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "k3s_ingress_acme_dns01_secret_access_key" {
  description = <<-EOT
    IAM secret access key for the ACME DNS-01 challenge's own route53
    provider -- dyndns's own traefik-acme-dns01 IAM user output. Same
    value as home-infra's k3s_ingress_acme_dns01_secret_access_key SOPS
    secret. Pass via TF_VAR_k3s_ingress_acme_dns01_secret_access_key at
    apply time.
  EOT
  type        = string
  sensitive   = true
}
