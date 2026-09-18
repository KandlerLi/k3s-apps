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
    (private package) -- shared verbatim with modules/sankey_export's
    own ghcr_pull secret (same account-scoped token, two different
    packages). Sourced directly from AWS Secrets Manager's
    k3s-apps/ghcr-pull-token group (secrets.tf's
    local.k3s_apps_ghcr_pull_token["token"]), split out of
    home-infra/home-agent 2026-09-12. Never given a default.
  EOT
  type        = string
  sensitive   = true
}

variable "home_agent_openai_api_key" {
  description = <<-EOT
    OpenAI API key for home_agent's Whisper speech-to-text relay only
    (audio.py) -- chat/completions moved to Anthropic 2026-09-18, see
    home_agent_anthropic_api_key. Sourced directly from AWS Secrets
    Manager's home-infra/home-agent group (secrets.tf's
    local.home_infra_home_agent["home_agent_openai_api_key"]).
  EOT
  type        = string
  sensitive   = true
}

variable "home_agent_anthropic_api_key" {
  description = <<-EOT
    Anthropic API key for home_agent's own chat/tool-use calls
    (agent.py's AnthropicMessagesProvider) -- replaced OpenAI's Responses
    API 2026-09-18, Whisper STT stays on OpenAI (see
    home_agent_openai_api_key). Sourced directly from AWS Secrets
    Manager's home-infra/home-agent group (secrets.tf's
    local.home_infra_home_agent["home_agent_anthropic_api_key"]). Never
    given a default.
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
    be revoked independently. Sourced directly from AWS Secrets
    Manager's home-infra/home-agent group (secrets.tf's
    local.home_infra_home_agent["nextcloud_tools_app_password"]).
    Never given a default.
  EOT
  type        = string
  sensitive   = true
}
