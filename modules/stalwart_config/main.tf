# Stalwart's runtime settings as code. These were originally set by hand in
# its admin UI (see docs/home-infra-docs/docs/runbooks/stalwart-mail-server.md);
# the provider adopts what already exists on first apply -- singletons
# adopt the live settings, and a non-singleton whose key already exists
# (like an allowed IP's address) is adopted rather than duplicated.
#
# Moved over one small slice at a time, each checked against a real plan
# before it is applied -- an unset optional attribute could otherwise be
# sent to the server as a default and quietly change a live setting. The
# authentication directory (the Authelia OIDC switch) deliberately stays
# manual: a mistake there locks out everything but the admin API key.

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

# --- Certificate for IMAPS/submission (mail clients) -----------------------
#
# Stalwart's own ACME, HTTP-01. Traefik owns 80/443, but the challenge
# still reaches Stalwart: port 80 redirects to https, and the `stalwart-api`
# router (modules/ingress) sends /.well-known/* on stalwart.jkandler.de to
# Stalwart without Authelia. DNS-01 was deliberately NOT used: it needs
# the domain's DNS management set to Automatic, which would let Stalwart
# write records into the Route53 zone that aws/dyndns and aws/ses-relay
# own (SPF, DMARC, MX ...) -- exactly the kind of second owner this
# workspace avoids.
#
# The contact is an outside address on purpose: Let's Encrypt's expiry
# warnings must still arrive if the mail server itself is what broke.
resource "stalwart_acme_provider" "letsencrypt" {
  contact        = ["julian.kandler@outlook.com"]
  directory      = "https://acme-v02.api.letsencrypt.org/directory"
  challenge_type = "Http01"
}

# The mail domain. It already exists (created by the setup wizard), so
# the provider adopts it. EVERY live value is mirrored here explicitly
# so adoption cannot reset anything to a provider default.
resource "stalwart_domain" "jkandler_de" {
  name               = "jkandler.de"
  is_enabled         = true
  allow_relaying     = false
  report_address_uri = "mailto:postmaster"

  sub_addressing = {
    type = "Enabled"
  }

  # DNS stays with Terraform (aws/dyndns, aws/ses-relay), never Stalwart.
  dns_management = {
    type = "Manual"
  }

  # Was "Automatic" (the wizard's default). Stalwart-side DKIM signing
  # must stay off: outbound mail goes through SES, which signs with its
  # own Easy DKIM, and a second DKIM-Signature header makes SES reject
  # the message outright. Automatic management could quietly recreate
  # the keys we deleted; Manual cannot.
  dkim_management = {
    type = "Manual"
  }

  # Only the hostname mail clients connect to. Hostnames are relative to
  # the domain ("stalwart" -> stalwart.jkandler.de); the apex would be
  # written in full. Which names Stalwart requests when this is left empty
  # isn't documented, so it's pinned explicitly -- names that don't
  # exist in DNS (imap., mta-sts., ...) would fail a whole HTTP-01 order.
  certificate_management = {
    type                      = "Automatic"
    acme_provider_id          = stalwart_acme_provider.letsencrypt.id
    subject_alternative_names = ["stalwart"]
  }
}

# --- Outbound relay through Amazon SES -------------------------------------
#
# All outbound mail goes through SES (aws/ses-relay), not direct-to-MX
# from the k3s VM's unproven IP. The password never reaches Stalwart's
# database: the route reads it from the SES_SMTP_PASSWORD env var that
# modules/stalwart injects from Secrets Manager. STARTTLS on 587, not
# implicit TLS.
resource "stalwart_mta_route_relay" "ses" {
  name                = "ses-relay"
  address             = "email-smtp.eu-central-1.amazonaws.com"
  port                = 587
  protocol            = "smtp"
  implicit_tls        = false
  allow_invalid_certs = false
  auth_username       = var.ses_smtp_username

  auth_secret = {
    type          = "EnvironmentVariable"
    variable_name = "SES_SMTP_PASSWORD"
  }
}

# Local recipients stay local; everything else goes to the SES route
# above (Stalwart's default is 'mx'). Only the route expression is set,
# so the schedule, TLS and connection strategies stay as they are.
resource "stalwart_mta_outbound_strategy" "this" {
  route = {
    match = [{
      if   = "is_local_domain(rcpt_domain)"
      then = "'local'"
    }]
    else = "'ses-relay'"
  }
}
