# This root stays local-apply-only, cluster-admin, by design -- see
# README.md. Same kubeconfig/tunnel setup as the app root always used
# (see this repo's own top-level README for the tunnel + kubeconfig
# steps); this root just needs it more rarely.
provider "kubernetes" {
  config_path = pathexpand("~/.kube/k3s-node-1.yaml")
}
