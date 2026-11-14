# Argo CD runs this app's workload and volumes from k3s-apps' argocd/; Secrets stay here. See README, "Argo CD".

removed {
  from = module.bulwark_data

  lifecycle {
    destroy = false
  }
}
