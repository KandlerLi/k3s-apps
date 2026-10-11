# Webmail preferences and admin state only; the mail lives in Stalwart.
moved {
  from = kubernetes_persistent_volume_claim_v1.bulwark
  to   = module.bulwark_data.kubernetes_persistent_volume_claim_v1.this
}

module "bulwark_data" {
  source = "../pvc_local_path"

  name = "bulwark"
  size = "1Gi"
}
