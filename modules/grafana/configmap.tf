# Same provider config as home-infra's grafana_dashboards_provider.yml.j2
# -- disableDeletion/editable: false, matching that role's own reasoning
# (dashboards are provisioned from files, not click-through UI state).
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

# Vendored copies of home-infra's own ansible/roles/monitoring/files/
# dashboards/*.json -- canonical originals stay there, same "sync a
# copy in, diff to confirm identical" pattern as nextcloud_tools_
# service.py. All five, unconditionally: unlike that role's own
# Blocky-conditional loop, this module has no non-Blocky mode to
# support -- Blocky stays enabled and host-bound regardless.
resource "kubernetes_config_map_v1" "grafana_dashboards" {
  metadata {
    name = "grafana-dashboards"
  }

  data = {
    for f in fileset("${path.module}/files/dashboards", "*.json") :
    f => file("${path.module}/files/dashboards/${f}")
  }
}
