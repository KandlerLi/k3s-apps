# Stalwart mail server; the web admin stays cluster-internal. See history.md ("Mail server").

# The SES relay credential via environment variables, rotatable, instead of typed into Stalwart's UI.
resource "kubernetes_secret_v1" "stalwart_ses_smtp" {
  metadata {
    namespace = "apps"
    name      = "stalwart-ses-smtp"
  }

  data = {
    SES_SMTP_USERNAME = var.stalwart_ses_smtp_username
    SES_SMTP_PASSWORD = var.stalwart_ses_smtp_password
  }

  type = "Opaque"
}
