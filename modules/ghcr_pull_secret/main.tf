# Shared dockerconfigjson credential for pulling a private GHCR image
# (ghcr.io/kandlerli/<image>) into this cluster -- extracted 2026-09-22
# (ponytail-audit) after modules/home_agent's and modules/sankey_export's
# own secret.tf files turned out to hold byte-identical copies of this
# resource, differing only in the Secret's own name and which token
# variable fed it.

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
