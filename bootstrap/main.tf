# Root module for this repo's "bootstrap" half: the self-hosted GitHub
# Actions runner itself (privileged almost by definition -- it's the
# thing CI runs on) plus the cluster-scoped PersistentVolumes (see
# storage.tf for why). Rare changes, applied locally with the k3s
# node's own cluster-admin kubeconfig -- see README.md. Everything else
# (Blocky, ingress, Grafana, home-agent, deluge, open-webui,
# landing-page, alertmanager) lives in the repo root instead, applied
# via CI with the narrowly-scoped ServiceAccount defined below.

module "github_runner" {
  source = "./modules/github_runner"

  github_runner_github_token = var.github_runner_github_token
  github_runner_repositories = var.github_runner_repositories

  github_runner_service_accounts = {
    k3s-apps = kubernetes_service_account_v1.k3s_apps_ci.metadata[0].name
  }
}

# The one ServiceAccount the app root's CI pipeline runs as -- created
# here, not there, since RBAC is itself privilege-defining and belongs
# in the rare/admin root, not the one it grants access to. Scoped to
# exactly the resource types the app root's 8 modules use in the
# default namespace; deliberately no persistentvolumes verb at all
# (see storage.tf's own comment for why that had to live here instead
# of being grantable by name).
#
# One SA for both the PR-time plan job and the production-gated apply
# job (not a separate narrower plan-only SA) -- terraform plan is
# inherently read-mostly, and the real write-gate stays the human
# approval click on the production environment, the same as every
# other CI-applied repo in this workspace. A stricter two-tier
# plan/apply SA split is a possible later refinement, not required now.
resource "kubernetes_service_account_v1" "k3s_apps_ci" {
  metadata {
    name = "k3s-apps-ci"
  }
}

resource "kubernetes_role_v1" "k3s_apps_ci" {
  metadata {
    name = "k3s-apps-ci"
  }

  rule {
    api_groups = [""]
    resources  = ["services", "configmaps", "secrets", "persistentvolumeclaims", "endpoints"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["apps"]
    resources  = ["deployments"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
  rule {
    api_groups = ["networking.k8s.io"]
    resources  = ["ingresses"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_role_binding_v1" "k3s_apps_ci" {
  metadata {
    name = "k3s-apps-ci"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "Role"
    name      = kubernetes_role_v1.k3s_apps_ci.metadata[0].name
  }

  subject {
    kind      = "ServiceAccount"
    name      = kubernetes_service_account_v1.k3s_apps_ci.metadata[0].name
    namespace = "default"
  }
}
