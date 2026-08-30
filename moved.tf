# Every resource here moved into modules/landing_page or modules/deluge
# during the 2026-08-30 module restructure. These blocks tell Terraform
# each new module-qualified address is the *same* real object as the old
# root-level address, not a new resource to create alongside a deleted
# old one -- `terraform plan` should show these as moves, with nothing
# touching the live cluster. Confirm that (0 to add, 0 to destroy) before
# applying.
#
# Safe to delete once a plan against the moved state comes back clean --
# Terraform doesn't need these once every state file that could still
# have the old addresses has been through an apply with them present.

moved {
  from = kubernetes_config_map_v1.landing_page_html
  to   = module.landing_page.kubernetes_config_map_v1.landing_page_html
}

moved {
  from = kubernetes_deployment_v1.landing_page
  to   = module.landing_page.kubernetes_deployment_v1.landing_page
}

moved {
  from = kubernetes_service_v1.landing_page
  to   = module.landing_page.kubernetes_service_v1.landing_page
}

moved {
  from = kubernetes_ingress_v1.landing_page
  to   = module.landing_page.kubernetes_ingress_v1.landing_page
}

moved {
  from = kubernetes_persistent_volume_v1.deluge_downloads
  to   = module.deluge.kubernetes_persistent_volume_v1.deluge_downloads
}

moved {
  from = kubernetes_persistent_volume_claim_v1.deluge_downloads
  to   = module.deluge.kubernetes_persistent_volume_claim_v1.deluge_downloads
}

moved {
  from = kubernetes_persistent_volume_v1.deluge_config
  to   = module.deluge.kubernetes_persistent_volume_v1.deluge_config
}

moved {
  from = kubernetes_persistent_volume_claim_v1.deluge_config
  to   = module.deluge.kubernetes_persistent_volume_claim_v1.deluge_config
}

moved {
  from = random_id.deluge_web_pwd_salt
  to   = module.deluge.random_id.deluge_web_pwd_salt
}

moved {
  from = kubernetes_secret_v1.deluge_web_conf
  to   = module.deluge.kubernetes_secret_v1.deluge_web_conf
}

moved {
  from = kubernetes_deployment_v1.deluge
  to   = module.deluge.kubernetes_deployment_v1.deluge
}

moved {
  from = kubernetes_service_v1.deluge_web
  to   = module.deluge.kubernetes_service_v1.deluge_web
}

moved {
  from = kubernetes_service_v1.deluge_peer
  to   = module.deluge.kubernetes_service_v1.deluge_peer
}

moved {
  from = kubernetes_ingress_v1.deluge
  to   = module.deluge.kubernetes_ingress_v1.deluge
}
