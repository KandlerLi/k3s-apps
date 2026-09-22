# Empty placeholder Secrets the Dashboard binary reads/writes at
# runtime (CSRF signing material, its own encryption key) -- it does
# NOT create these itself if missing, despite get/update/delete
# access; it panics instead. The official recommended.yaml manifest
# ships both empty up front for this reason.
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
