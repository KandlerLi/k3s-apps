# Argo CD runs this app's workload from k3s-apps' argocd/; Secrets and PVCs stay here. See README, "Argo CD".

removed {
  from = kubernetes_cron_job_v1.sankey_export

  lifecycle {
    destroy = false
  }
}
