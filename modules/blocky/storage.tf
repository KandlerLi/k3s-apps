# Small PVC for Postgres's own query-log data -- unlike Grafana's/
# Alertmanager's own "start fresh, no PVC" choice, this holds a real,
# if bounded and short-lived (7-day retention), rolling dataset that's
# worth surviving an ordinary Pod restart rather than resetting every
# time. Confirmed with Julian: start fresh (the *existing* homeserver
# data isn't migrated), but the new deployment still persists going
# forward -- the same reasoning modules/ingress's own acme.json PVC
# used for a different kind of small, disposable, k3s-owned state.
# storage_class_name = "local-path" explicitly (not left unset) --
# matching modules/deluge's own storage.tf finding that an unset/empty
# value gets serialized identically by this provider, confusing k3s's
# own DefaultStorageClass admission controller.
#
# wait_until_bound = false: same chicken-and-egg hang modules/ingress's
# own acme.json PVC hit and fixed -- local-path's WaitForFirstConsumer
# binding mode only binds once a Pod references it, but Terraform
# creates this PVC before the Deployment that would do that.
#
# Shape lives in modules/pvc_local_path (extracted 2026-09-22,
# ponytail-audit -- see that module's own comment).
moved {
  from = kubernetes_persistent_volume_claim_v1.blocky_postgres
  to   = module.blocky_postgres.kubernetes_persistent_volume_claim_v1.this
}

module "blocky_postgres" {
  source = "../pvc_local_path"

  name = "blocky-postgres"
  size = "256Mi"
}
