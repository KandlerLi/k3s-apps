# Deliberately no S3 backend yet, unlike every other Terraform repo in
# this homelab -- that would need AWS credentials wherever this runs,
# for no real benefit yet. State stays local for now; move to a remote
# backend once this pattern is trusted enough to matter if the local
# copy is lost.
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
