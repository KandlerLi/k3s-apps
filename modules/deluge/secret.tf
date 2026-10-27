# Deluge requires a password, so a blank one: Authelia's MFA session already gates this route.

# Stable across applies unless tainted.
resource "random_id" "deluge_web_pwd_salt" {
  byte_length = 20
}

locals {
  # Deluge's sha1(salt) + sha1(password) scheme; the password is empty, so sha1(salt).
  deluge_web_pwd_sha1 = sha1(random_id.deluge_web_pwd_salt.hex)

  # Deluge's file_version=2 format: a header object directly followed by the content object.
  deluge_web_conf = join("", [
    jsonencode({
      file   = 2
      format = 1
    }),
    jsonencode({
      enabled_plugins = []
      default_daemon  = ""
      pwd_salt        = random_id.deluge_web_pwd_salt.hex
      pwd_sha1        = local.deluge_web_pwd_sha1
      # A year-long sliding session: Authelia already gates the route.
      session_timeout          = 31536000
      sessions                 = {}
      sidebar_show_zero        = false
      sidebar_multiple_filters = true
      show_session_speed       = false
      show_sidebar             = true
      theme                    = "gray"
      first_login              = false
      language                 = ""
      base                     = "/"
      interface                = "0.0.0.0"
      port                     = 8112
      https                    = false
      pkey                     = "ssl/daemon.pkey"
      cert                     = "ssl/daemon.cert"
    }),
  ])
}

resource "kubernetes_secret_v1" "deluge_web_conf" {
  metadata {
    namespace = "apps"
    name      = "deluge-web-conf"
  }

  data = {
    "web.conf" = local.deluge_web_conf
  }

  type = "Opaque"
}
