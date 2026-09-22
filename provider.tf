# Two auth modes, chosen by var.in_cluster:
#
# - false (the default, for a human's own local apply): config_path.
#   The kubernetes provider does NOT read the standard KUBECONFIG
#   environment variable the way kubectl does -- an earlier version of
#   this file relied on that and silently fell back to querying
#   http://localhost. config_path is set explicitly instead. See
#   README.md for the tunnel + kubeconfig setup this path assumes.
# - true (set only by this repo's own CI workflows): the standard
#   in-cluster auth triple (host + token + CA, from the ServiceAccount
#   token Kubernetes automatically mounts). Terraform's own conditional
#   expressions short-circuit file() in the untaken branch, so this is
#   safe to leave as the unconditional default rather than needing its
#   own separate provider block.
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

# Auth is ambient in both apply modes -- CI's own AWS OIDC role
# assumption for the in-cluster case, a human's own `aws login` session
# otherwise. Used by secrets.tf's own data sources.
provider "aws" {
  region = "eu-central-1"
}

# Stalwart's own settings, as code (modules/stalwart_config). Talks to
# the management API over the private Service, never the public
# hostname (Authelia would intercept it). Authenticates with an admin
# API key from Secrets Manager -- a Bearer token, which Stalwart
# validates as an internal credential regardless of its Authentication
# Directory setting, so this keeps working while SSO is on.
#
# COUPLING WORTH KNOWING: unlike everything else in this root, this
# provider talks to a live server at plan time -- a Stalwart outage
# fails every plan in this repo. See
# docs/home-infra-ai-context's current-state.md ("Mail server") for why
# this was accepted over a separate root, and the -target workaround.
provider "stalwart" {
  endpoint = coalesce(var.stalwart_endpoint, var.in_cluster ? "http://stalwart-internal.default.svc.cluster.local:8080" : "http://127.0.0.1:18083")
  token    = local.k3s_apps_stalwart["stalwart_api_token"]
}
