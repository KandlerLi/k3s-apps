# Deliberately no S3 backend yet, unlike every other Terraform repo in
# this homelab -- that would need this VM to hold AWS credentials, which
# it doesn't have and doesn't need for a learning cluster. State stays
# local on the VM for now; move to a remote backend once this pattern
# is trusted enough to matter if the VM's disk is lost.
provider "kubernetes" {
  # Runs directly on the k3s VM itself, using the kubeconfig k3s already
  # writes there -- the same file kubectl already points at by default.
  config_path = "/etc/rancher/k3s/k3s.yaml"
}
