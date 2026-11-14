variable "k3s_ingress_acme_dns01_access_key_id" {
  description = <<-EOT
    IAM access key ID for the ACME DNS-01 challenge's own route53
    provider -- dyndns's own traefik-acme-dns01 IAM user output.
    Sourced directly from AWS Secrets Manager's home-infra/ingress
    group (secrets.tf's
    local.home_infra_ingress["k3s_ingress_acme_dns01_access_key_id"]).
  EOT
  type        = string
  sensitive   = true
}

variable "k3s_ingress_acme_dns01_secret_access_key" {
  description = <<-EOT
    IAM secret access key for the ACME DNS-01 challenge's own route53
    provider -- dyndns's own traefik-acme-dns01 IAM user output.
    Sourced directly from AWS Secrets Manager's home-infra/ingress
    group (secrets.tf's
    local.home_infra_ingress["k3s_ingress_acme_dns01_secret_access_key"]).
  EOT
  type        = string
  sensitive   = true
}
