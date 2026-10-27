# Shared pull credential for private GHCR images (home_agent, sankey_export).

variable "name" {
  description = "Kubernetes Secret name for this dockerconfigjson credential."
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace of the Secret."
  type        = string
}

variable "token" {
  description = "GHCR PAT (read:packages) used to pull the private image."
  type        = string
  sensitive   = true
}

resource "kubernetes_secret_v1" "this" {
  metadata {
    name      = var.name
    namespace = var.namespace
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
