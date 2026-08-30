variable "deluge_web_password" {
  description = <<-EOT
    Deluge's own web UI login password (separate from the shared
    Traefik Basic Auth in front of everything -- Deluge cannot disable
    its own login, per home-infra's deluge role). Same value as
    home-infra's deluge_web_password SOPS secret.

    Passed in from the root module's own variable of the same name --
    never given a default here either.
  EOT
  type        = string
  sensitive   = true
}
