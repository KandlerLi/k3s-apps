variable "ses_smtp_username" {
  description = "SES SMTP username for the outbound relay route -- the same credential modules/stalwart puts in SES_SMTP_USERNAME."
  type        = string
  sensitive   = true
}
