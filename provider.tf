# var.in_cluster: false uses config_path (the provider ignores KUBECONFIG), true uses the
# ServiceAccount token CI runs with. See the README.
variable "in_cluster" {
  description = <<-EOT
    Selects which of the two provider auth modes above applies. Left
    false for a human's own local apply; this repo's own CI workflows
    set TF_VAR_in_cluster=true explicitly.
  EOT
  type        = bool
  default     = false
}

provider "kubernetes" {
  config_path = var.in_cluster ? null : pathexpand("~/.kube/k3s-node-1.yaml")

  host                   = var.in_cluster ? "https://kubernetes.default.svc" : null
  cluster_ca_certificate = var.in_cluster ? file("/var/run/secrets/kubernetes.io/serviceaccount/ca.crt") : null
  token                  = var.in_cluster ? file("/var/run/secrets/kubernetes.io/serviceaccount/token") : null
}

# Ambient auth: CI's OIDC role, or a local aws login session.
provider "aws" {
  region = "eu-central-1"
}

# Talks to the management API over the private Service, never the public hostname Authelia guards.
provider "stalwart" {
  endpoint = coalesce(var.stalwart_endpoint, var.in_cluster ? "http://stalwart-internal.apps.svc.cluster.local:8080" : "http://127.0.0.1:18083")
  token    = local.k3s_apps_stalwart["stalwart_api_token"]
}
