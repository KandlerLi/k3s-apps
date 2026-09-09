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
