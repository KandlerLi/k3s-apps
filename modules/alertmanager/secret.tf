# A Secret, not a ConfigMap, because the rendered file carries the real
# SES SMTP password in plaintext -- matching home-infra's own no_log:
# true on the equivalent Ansible task, and Grafana's own
# grafana-datasources Secret for the same reason.
resource "kubernetes_secret_v1" "alertmanager_config" {
  metadata {
    name = "alertmanager-config"
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
