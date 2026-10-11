# Postgres's query-log data: bounded (7-day retention) but worth keeping across restarts.
moved {
  from = kubernetes_persistent_volume_claim_v1.blocky_postgres
  to   = module.blocky_postgres.kubernetes_persistent_volume_claim_v1.this
}

module "blocky_postgres" {
  source = "../pvc_local_path"

  name = "blocky-postgres"
  size = "256Mi"
}
