# Bulwark's own state: user preferences (encrypted settings sync) and its
# admin config/state, all under /app/data (see main.tf). The mail itself
# lives in Stalwart, not here -- losing this only resets webmail
# preferences.
#
# storage_class_name = "local-path" explicitly and wait_until_bound =
# false, for the same reasons modules/blocky's own storage.tf documents.
# Shape lives in modules/pvc_local_path (extracted 2026-09-22,
# ponytail-audit -- see that module's own comment).
moved {
  from = kubernetes_persistent_volume_claim_v1.bulwark
  to   = module.bulwark_data.kubernetes_persistent_volume_claim_v1.this
}

module "bulwark_data" {
  source = "../pvc_local_path"

  name = "bulwark"
  size = "1Gi"
}
