# nextcloud_tools_service.py has no third-party dependencies (stdlib
# only, confirmed reading home-infra's own requirements -- it has none),
# so it doesn't need its own built image the way home_agent's actual
# agent does. A stock python:3.13-slim-bookworm image plus this source
# mounted in is the whole thing -- real source copied from home-infra's
# ansible/roles/nextcloud_tools/files/, not fabricated.
resource "kubernetes_config_map_v1" "nextcloud_tools_source" {
  metadata {
    name = "nextcloud-tools-source"
  }

  data = {
    "nextcloud_tools_service.py" = file("${path.module}/files/nextcloud_tools_service.py")
  }
}
