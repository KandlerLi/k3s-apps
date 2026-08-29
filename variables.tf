variable "deluge_web_password" {
  description = <<-EOT
    Deluge's own web UI login password (separate from the shared
    Traefik Basic Auth in front of everything -- Deluge cannot disable
    its own login, per home-infra's deluge role). Same value as
    home-infra's deluge_web_password SOPS secret.

    Never given a default and never written to a file in this repo --
    pass it via the TF_VAR_deluge_web_password environment variable at
    apply time.
  EOT
  type        = string
  sensitive   = true
}
