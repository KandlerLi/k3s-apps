variable "home_agent_image" {
  description = <<-EOT
    Full ghcr.io/kandlerli/home-agent reference, pinned by digest --
    built and pushed by home-infra's build-home-agent.yml workflow on
    its self-hosted CI runner, never on the homeserver itself. Update
    this by hand after each meaningful build (see that workflow's
    "Print pushed image digest" step output).
  EOT
  type        = string
}

variable "home_agent_ghcr_token" {
  description = <<-EOT
    Read-scoped GitHub PAT for pulling ghcr.io/kandlerli/home-agent
    (private package). Same value as home-infra's home_agent_ghcr_token
    SOPS secret -- pass it via TF_VAR_home_agent_ghcr_token at apply
    time, never given a default.
  EOT
  type        = string
  sensitive   = true
}

variable "home_agent_openai_api_key" {
  description = <<-EOT
    Same value as home-infra's home_agent_openai_api_key SOPS secret.
    Pass via TF_VAR_home_agent_openai_api_key at apply time.
  EOT
  type        = string
  sensitive   = true
}

variable "nextcloud_tools_app_password" {
  description = <<-EOT
    A Nextcloud app password dedicated to this k3s copy of
    nextcloud_tools -- deliberately NOT the same token home-infra's own
    nextcloud_tools uses (generated separately via
    `occ user:auth-tokens:add --name=home-agent-readonly-k3s
    home-agent`, matching ADR 0008's own generation method), so it can
    be revoked independently. Never given a default; pass it via
    TF_VAR_nextcloud_tools_app_password at apply time.
  EOT
  type        = string
  sensitive   = true
}
