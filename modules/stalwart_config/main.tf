# Stalwart's runtime settings as code, adopted from the admin UI: see the stalwart-mail-server runbook.

# Bulwark calls JMAP cross-origin; Stalwart only has allow-all CORS.
resource "stalwart_http" "this" {
  use_permissive_cors = true
}

# Traefik is Stalwart's only HTTP client, so automatic IP banning must never block it.
resource "stalwart_allowed_ip" "k3s_pods" {
  address = "10.42.0.0/16"
  reason  = "k3s Pod network (Traefik); Stalwart's IP banning must never block the ingress"
}

# Stalwart's own ACME (HTTP-01) for the IMAPS/submission certificate.
resource "stalwart_acme_provider" "letsencrypt" {
  contact        = ["julian.kandler@outlook.com"]
  directory      = "https://acme-v02.api.letsencrypt.org/directory"
  challenge_type = "Http01"
}

# Adopted from the wizard; every live value is mirrored so adoption resets nothing.
resource "stalwart_domain" "jkandler_de" {
  name               = "jkandler.de"
  is_enabled         = true
  allow_relaying     = false
  report_address_uri = "mailto:postmaster"

  sub_addressing = {
    type = "Enabled"
  }

  # DNS stays with Terraform (dyndns, ses-relay).
  dns_management = {
    type = "Manual"
  }

  # Manual and off: SES signs with Easy DKIM and rejects a second DKIM-Signature.
  dkim_management = {
    type = "Manual"
  }

  # Only the hostname mail clients connect to.
  certificate_management = {
    type                      = "Automatic"
    acme_provider_id          = stalwart_acme_provider.letsencrypt.id
    subject_alternative_names = ["stalwart"]
  }
}

# All outbound mail relays through SES, not direct-to-MX from an unproven IP.
resource "stalwart_mta_route_relay" "ses" {
  name                = "ses-relay"
  description         = "Outbound via Amazon SES SMTP"
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

# Local recipients stay local, everything else goes to the SES route.
resource "stalwart_mta_outbound_strategy" "this" {
  route = {
    match = [{
      if   = "is_local_domain(rcpt_domain)"
      then = "'local'"
    }]
    else = "'ses-relay'"
  }
}
