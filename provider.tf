# Deliberately no S3 backend yet, unlike every other Terraform repo in
# this homelab -- that would need AWS credentials wherever this runs,
# for no real benefit yet. State stays local for now; move to a remote
# backend once this pattern is trusted enough to matter if the local
# copy is lost.
provider "kubernetes" {
  # No hardcoded config_path: the k3s VM's network is only reachable
  # from the homeserver, not directly from a laptop (confirmed live --
  # 192.168.101.0/24 exists only as a link-local route on the
  # homeserver itself), so this deliberately runs from wherever an SSH
  # tunnel to the apiserver is open, not fixed to one machine. Point it
  # at the right kubeconfig the standard way instead:
  #   KUBECONFIG=~/.kube/k3s-node-1.yaml terraform apply
  # See README.md for the tunnel + kubeconfig setup.
}
