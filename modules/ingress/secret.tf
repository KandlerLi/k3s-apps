# htpasswd-format users file, same one-line shape as home-infra's own
# templates/users.j2 -- a Secret, not a ConfigMap, since it carries a
# real password hash.
resource "kubernetes_secret_v1" "ingress_users" {
  metadata {
    name = "ingress-users"
  }

  data = {
    users = "julian:${var.shared_ingress_auth_password_hash}"
  }

  type = "Opaque"
}
