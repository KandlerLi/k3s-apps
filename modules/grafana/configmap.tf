# Provisioned from files: no deletion, no editing in the UI.
resource "kubernetes_config_map_v1" "grafana_dashboard_provider" {
  metadata {
    name = "grafana-dashboard-provider"
  }

  data = {
    "dashboards.yml" = <<-EOT
      apiVersion: 1

      providers:
        - name: monitoring
          orgId: 1
          folder: ""
          type: file
          disableDeletion: true
          editable: false
          updateIntervalSeconds: 60
          options:
            path: /var/lib/grafana-dashboards
    EOT
  }
}

# Vendored from home-infra's monitoring/files/dashboards; the originals stay canonical there.
resource "kubernetes_config_map_v1" "grafana_dashboards" {
  metadata {
    name = "grafana-dashboards"
  }

  data = {
    for f in fileset("${path.module}/files/dashboards", "*.json") :
    f => file("${path.module}/files/dashboards/${f}")
  }
}
