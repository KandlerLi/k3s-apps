# Deluge's own login (not the shared Traefik Basic Auth) -- it has no
# "no login required" mode (confirmed against its auth.py source:
# check_password() returns False for every password when pwd_sha1 is
# missing, permanently locking out login rather than bypassing it),
# so this has to exist. Same web.conf shape and same salted-SHA1
# scheme home-infra's deluge role already uses
# (web.conf.j2/tasks/main.yml), reproduced here in Terraform instead
# of a Jinja template.
#
# Password deliberately blank (an empty string, not a secret) as of
# 2026-09-08 -- now that Authelia gates torrent.jkandler.de with real
# MFA'd session auth in front of this, Deluge's own login is redundant
# friction, not a meaningful second security boundary. Blank isn't
# "disabled" (see above -- Deluge has no such mode), just a login
# screen with nothing to remember: submit an empty password field once
# and, combined with the year-long session_timeout below, you won't
# see it again in practice.

# Stable across applies once created -- doesn't regenerate just
# because something else in this config changes, only if explicitly
# tainted.
resource "random_id" "deluge_web_pwd_salt" {
  byte_length = 20
}

locals {
  # Matches deluge/ui/web/auth.py's Auth._change_password() exactly:
  # sha1(salt); sha1.update(password) == sha1(salt + password), since
  # SHA1 produces the same digest for sequential updates as for the
  # concatenated input in one call -- the same fact home-infra's own
  # deluge role comment verifies. random_id's .hex output is already
  # lowercase, matching what Deluge itself writes. Password is a
  # literal empty string here (see this file's own top comment for
  # why), so this is just sha1(salt) -- nothing appended.
  deluge_web_pwd_sha1 = sha1(random_id.deluge_web_pwd_salt.hex)

  # Deluge's ConfigManager file_version=2 format: a header object
  # immediately followed by the content object, concatenated with no
  # separator between them -- confirmed against home-infra's own
  # web.conf.j2 template, which this reproduces. JSON key order
  # doesn't need to match byte-for-byte (Deluge parses this as JSON,
  # not a literal string), only the two-objects-concatenated shape and
  # every key the real template writes.
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
      # Deluge has no "no login required" mode -- confirmed directly
      # against its own auth.py source (deluge-torrent/deluge on
      # GitHub): check_password() has no bypass, no special password
      # value, no config flag to skip it. What IS real: its own
      # session cookie refreshes on every request while active
      # (make_expires(session_timeout) re-runs per valid request, see
      # auth.py's _clean_sessions()/get_session_id()), so this is a
      # sliding idle-timeout, not a fixed re-login schedule. Bumped
      # from the 3600s (1 hour) default to a year, 2026-09-08, now
      # that Authelia gates torrent.jkandler.de with real MFA'd
      # session auth in front of this -- a long-lived Deluge-internal
      # session is low risk (anyone who could reach this login page at
      # all has already passed Authelia), and this makes Deluge's own
      # login effectively one-time in practice without literally
      # disabling auth, which isn't possible.
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
