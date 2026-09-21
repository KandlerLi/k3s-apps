variable "home_agent_image" {
  description = <<-EOT
    Full ghcr.io/kandlerli/home-agent reference, pinned by digest. See
    modules/home_agent's own variable of the same name.
  EOT
  type        = string
}

variable "sankey_export_image" {
  description = <<-EOT
    Full ghcr.io/kandlerli/sankey-export reference, pinned by digest.
    See modules/sankey_export's own variable of the same name.
  EOT
  type        = string
}

variable "stalwart_endpoint" {
  description = <<-EOT
    Base URL the Stalwart provider talks to. Left null it follows
    var.in_cluster: CI (in the cluster) uses the Service's in-cluster DNS
    name; a human's local run uses a `kubectl port-forward
    svc/stalwart-internal 18083:8080` on localhost. Never the public
    stalwart.jkandler.de name -- that sits behind Authelia forward-auth,
    which would redirect the provider's API calls to a login page.
  EOT
  type        = string
  default     = null
}
