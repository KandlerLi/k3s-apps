# Gained a real S3 backend 2026-09-03 (see versions.tf) once this root
# started being applied by CI -- see that file's own comment for why.
provider "kubernetes" {
  # NOTE: the kubernetes provider does NOT read the standard KUBECONFIG
  # environment variable the way kubectl does -- confirmed against its
  # own docs (hashicorp/terraform-provider-kubernetes, docs/index.md):
  # "The provider does not use the KUBECONFIG environment variable by
  # default." An earlier version of this file relied on that and just
  # silently fell back to querying http://localhost, which is why
  # `terraform apply` failed with a connection-refused error instead of
  # a clear "no config" one. config_path is set explicitly here instead
  # so this doesn't depend on how the shell invoking terraform is set
  # up. See README.md for the tunnel + kubeconfig setup this path
  # assumes.
  config_path = pathexpand("~/.kube/k3s-node-1.yaml")
}
