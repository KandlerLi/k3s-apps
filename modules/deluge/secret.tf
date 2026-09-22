# Deluge's own login has no "no login required" mode (check_password()
# returns False for every password when pwd_sha1 is missing) -- so
# this exists, but the password is deliberately blank: Authelia
# already gates torrent.jkandler.de with real MFA'd session auth in
# front of this, so Deluge's own login is redundant friction, not a
# meaningful second boundary. Same web.conf shape/salted-SHA1 scheme as
# home-infra's deluge role.

# Stable across applies once created -- doesn't regenerate just
# because something else in this config changes, only if explicitly
# tainted.
resource "random_id" "deluge_web_pwd_salt" {
  byte_length = 20
}

locals {
  # Matches deluge/ui/web/auth.py's Auth._change_password(): sha1(salt)
  # concatenated with sha1(password) is equivalent to sha1(salt +
  # password). Password is a literal empty string, so this is just
  # sha1(salt).
  deluge_web_pwd_sha1 = sha1(random_id.deluge_web_pwd_salt.hex)

  # Deluge's ConfigManager file_version=2 format: a header object
  # immediately followed by the content object, concatenated with no
  # separator between them. JSON key order doesn't need to match
  # byte-for-byte, only this shape and every key the real template
  # writes.
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
      # A sliding idle-timeout (refreshes on every request), bumped
      # from Deluge's 3600s default to a year -- Authelia already gates
      # this route with real MFA'd session auth, so a long-lived
      # Deluge-internal session is low risk and makes its login
      # effectively one-time in practice.
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
    name = "deluge-web-conf"
  }

  data = {
    "web.conf" = local.deluge_web_conf
  }

  type = "Opaque"
}
