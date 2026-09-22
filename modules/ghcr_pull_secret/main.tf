# Shared dockerconfigjson credential for pulling a private GHCR image
# (ghcr.io/kandlerli/<image>) into this cluster. Used by
# modules/home_agent and modules/sankey_export.

variable "name" {
  description = "Kubernetes Secret name for this dockerconfigjson credential."
  type        = string
}

variable "token" {
  description = "GHCR PAT (read:packages) used to pull the private image."
  type        = string
  sensitive   = true
}

resource "kubernetes_secret_v1" "this" {
  metadata {
    name = var.name
  }

  type = "kubernetes.io/dockerconfigjson"

  data = {
    ".dockerconfigjson" = jsonencode({
      auths = {
        "ghcr.io" = {
          username = "KandlerLi"
          password = var.token
          auth     = base64encode("KandlerLi:${var.token}")
        }
      }
    })
  }
}
