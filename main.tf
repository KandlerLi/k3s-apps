# Root module: wires the two workload modules together. Each module is
# self-contained (its own resources, its own files/ where relevant) so a
# third service can be added the same way -- a new modules/<service>/
# directory plus a module block here -- without touching an existing
# one's code.

module "landing_page" {
  source = "./modules/landing_page"
}

module "deluge" {
  source = "./modules/deluge"

  deluge_web_password = var.deluge_web_password
}
