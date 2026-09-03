# Gained a real S3 backend 2026-09-03 (see versions.tf) once this root
# started being applied by CI -- see that file's own comment for why.
#
# Two auth modes, chosen by var.in_cluster:
#
# - false (the default, for a human's own local apply): config_path, as
#   before. NOTE: the kubernetes provider does NOT read the standard
#   KUBECONFIG environment variable the way kubectl does -- confirmed
#   against its own docs (hashicorp/terraform-provider-kubernetes,
#   docs/index.md): "The provider does not use the KUBECONFIG
#   environment variable by default." An earlier version of this file
#   relied on that and just silently fell back to querying
#   http://localhost, which is why `terraform apply` failed with a
#   connection-refused error instead of a clear "no config" one.
#   config_path is set explicitly instead so this doesn't depend on how
#   the shell invoking terraform is set up. See README.md for the
#   tunnel + kubeconfig setup this path assumes.
# - true (set only by this repo's own CI workflows, which run on the
#   self-hosted runner living inside this same cluster): the standard
#   in-cluster auth triple (host + token + CA, read from the
#   ServiceAccount token Kubernetes automatically mounts into any Pod
#   with automount_service_account_token enabled -- see the separate
#   k3s-bootstrap repo's own main.tf for the k3s-apps-ci ServiceAccount
#   and its modules/github_runner for the wiring of it onto this repo's
#   own runner Deployment specifically). Confirmed live (2026-09-03) that
#   Terraform's own conditional expressions short-circuit file() in the
#   untaken branch -- a bogus path in the *other* branch doesn't error
#   here, so this is safe to leave as the unconditional default rather
#   than needing its own separate provider block.
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
