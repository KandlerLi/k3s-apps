# Root module: one module block per service under modules/. See the README.

# Argo CD deploys these from argocd/ now: see README, "Argo CD".
removed {
  from = module.landing_page

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.headlamp

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.qbittorrent

  lifecycle {
    destroy = false
  }
}

module "home_agent" {
  source = "./modules/home_agent"
}

module "open_webui" {
  source = "./modules/open_webui"

  depends_on = [module.home_agent]
}

module "sankey_export" {
  source = "./modules/sankey_export"
}

# kube-state-metrics moved to argocd/kube-state-metrics, the node-exporter DaemonSet to k3s-bootstrap.
removed {
  from = module.node_exporter

  lifecycle {
    destroy = false
  }
}

module "grafana" {
  source = "./modules/grafana"
}

module "alertmanager" {
  source = "./modules/alertmanager"
}

module "blocky" {
  source = "./modules/blocky"
}

module "stalwart" {
  source = "./modules/stalwart"
}

# Stalwart's runtime settings moved to the stalwart-config repo, which imported them.
removed {
  from = module.stalwart_config

  lifecycle {
    destroy = false
  }
}

module "bulwark" {
  source = "./modules/bulwark"
}

module "paperless" {
  source = "./modules/paperless"
}

module "vaultwarden" {
  source = "./modules/vaultwarden"
}

module "authelia" {
  source = "./modules/authelia"
}

module "ingress" {
  source = "./modules/ingress"
}
