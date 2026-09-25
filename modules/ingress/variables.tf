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

variable "routes" {
  description = <<-EOT
    Traefik routes contributed by app modules' ingress_routes outputs,
    keyed by router name (also used as its service and middleware name
    prefix). url is the in-cluster backend; forward_auth puts Authelia
    in front; rate_limit and max_body_bytes add those middlewares.
  EOT
  type = map(object({
    rule           = string
    priority       = optional(number)
    url            = string
    forward_auth   = bool
    rate_limit     = optional(object({ average = number, burst = number }))
    max_body_bytes = optional(number)
  }))
}
