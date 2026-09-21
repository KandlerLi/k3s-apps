# Stalwart's runtime settings as code. These were originally set by hand in
# its admin UI (see docs/home-infra-docs/docs/runbooks/stalwart-mail-server.md);
# the provider adopts what already exists on first apply -- singletons
# adopt the live settings, and a non-singleton whose key already exists
# (like an allowed IP's address) is adopted rather than duplicated.
#
# FIRST SLICE ONLY, deliberately small: prove the provider's plan is clean
# against the live server before moving anything riskier (the
# authentication directory, SES relay route, ACME) under management.
# Every resource here is checked with a local `terraform plan` before
# CI ever applies it -- an unset optional attribute could otherwise be
# sent to the server as a default and quietly change a live setting.

# Bulwark's browser-side JMAP calls to stalwart.jkandler.de come from
# https://mail.jkandler.de, so cross-origin requests must be allowed.
# Stalwart only offers on/off (allow all origins), not a per-origin list;
# every call still needs valid credentials.
resource "stalwart_http" "this" {
  use_permissive_cors = true
}

# The k3s Pod network. Traefik is the only client Stalwart's HTTP listener
# ever sees, so Stalwart's automatic IP banning must never block it: it
# once did, and every visitor got a "Bad Gateway" until it was cleared.
resource "stalwart_allowed_ip" "k3s_pods" {
  address = "10.42.0.0/16"
  reason  = "k3s Pod network (Traefik); Stalwart's IP banning must never block the ingress"
}
