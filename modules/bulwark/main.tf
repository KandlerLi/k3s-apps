# Bulwark's Secrets (its session secret lives in Terraform state) and checksums; Argo CD runs the workload. See history.md ("Mail server").

resource "random_id" "session" {
  byte_length = 32
}

resource "kubernetes_secret_v1" "bulwark_session" {
  metadata {
    namespace = "apps"
    name      = "bulwark-session"
  }

  data = {
    SESSION_SECRET = random_id.session.b64_std
  }

  type = "Opaque"
}

# Authelia OIDC for Bulwark's own login screen, separate from the forward-auth gate in front of it.
resource "kubernetes_secret_v1" "bulwark_oidc" {
  metadata {
    namespace = "apps"
    name      = "bulwark-oidc"
  }

  data = {
    OAUTH_CLIENT_SECRET = var.bulwark_oidc_client_secret
  }

  type = "Opaque"
}

# Argo CD deploys the Deployment and Service from argocd/bulwark now: see README, "Argo CD".
removed {
  from = kubernetes_deployment_v1.bulwark

  lifecycle {
    destroy = false
  }
}

removed {
  from = kubernetes_service_v1.bulwark

  lifecycle {
    destroy = false
  }
}

# Restarts Argo CD's Pod when a Secret here changes; Argo CD's manifest leaves these annotations out.
resource "kubernetes_annotations" "bulwark_checksums" {
  api_version   = "apps/v1"
  kind          = "Deployment"
  field_manager = "terraform-secret-checksums"
  force         = true

  metadata {
    namespace = "apps"
    name      = "bulwark"
  }

  template_annotations = {
    "checksum/session" = sha256(random_id.session.b64_std)
    "checksum/oidc"    = sha256(jsonencode(kubernetes_secret_v1.bulwark_oidc.data))
  }
}
