# A Secret: the rendered file carries the SES SMTP password.
resource "kubernetes_secret_v1" "alertmanager_config" {
  metadata {
    name      = "alertmanager-config"
    namespace = "monitoring"
  }

  data = {
    "alertmanager.yml" = templatefile("${path.module}/templates/alertmanager.yml.tftpl", {
      alert_email       = "julian.kandler@outlook.com"
      ses_from_address  = "alerts@jkandler.de"
      ses_smtp_host     = "email-smtp.eu-central-1.amazonaws.com:587"
      ses_smtp_username = var.alertmanager_ses_smtp_username
      ses_smtp_password = var.alertmanager_ses_smtp_password
    })
  }

  type = "Opaque"
}
