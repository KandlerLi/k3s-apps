# Empty placeholder Secrets the Dashboard binary itself reads/writes
# at runtime (CSRF token signing material, and its own internal
# encryption key) -- it does NOT create these itself if they're
# missing, despite get/update/delete access; it panics instead
# ("secrets \"kubernetes-dashboard-csrf\" not found"), confirmed live.
# The official recommended.yaml manifest ships both as empty Secret
# objects up front for exactly this reason. Fine for this CI-applied
# root to create, unlike the RBAC in k3s-bootstrap's own
# dashboard_rbac.tf: an empty Secret object carries no privilege of its
# own, and k3s-apps-ci's Role already holds a plain, unscoped "create"
# verb on secrets for every other module's own app Secrets here --
# nothing new is being granted by adding these two.
resource "kubernetes_secret_v1" "kubernetes_dashboard_csrf" {
  metadata {
    name = "kubernetes-dashboard-csrf"
  }

  type = "Opaque"
}

resource "kubernetes_secret_v1" "kubernetes_dashboard_key_holder" {
  metadata {
    name = "kubernetes-dashboard-key-holder"
  }

  type = "Opaque"
}
