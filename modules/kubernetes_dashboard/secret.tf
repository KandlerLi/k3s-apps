# Empty Secrets the Dashboard needs at runtime; it panics instead of creating them.
resource "kubernetes_secret_v1" "kubernetes_dashboard_csrf" {
  metadata {
    namespace = "apps"
    name      = "kubernetes-dashboard-csrf"
  }

  type = "Opaque"
}

resource "kubernetes_secret_v1" "kubernetes_dashboard_key_holder" {
  metadata {
    namespace = "apps"
    name      = "kubernetes-dashboard-key-holder"
  }

  type = "Opaque"
}
