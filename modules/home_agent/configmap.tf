# Stdlib-only, so it runs from a ConfigMap on a stock Python image, no build needed.
resource "kubernetes_config_map_v1" "nextcloud_tools_source" {
  metadata {
    name = "nextcloud-tools-source"
  }

  data = {
    "nextcloud_tools_service.py" = file("${path.module}/files/nextcloud_tools_service.py")
  }
}
