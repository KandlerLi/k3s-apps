# home_agent_image isn't a secret -- just a pinned public digest string
# (the private part is home_agent_ghcr_token, which authenticates the
# pull; this value alone doesn't grant access to anything). Tracked
# here instead of passed via TF_VAR so `terraform plan`/`apply` pick it
# up automatically -- update by hand after each meaningful build (see
# home-infra's build-home-agent.yml workflow's "Print pushed image
# digest" step output).
home_agent_image = "ghcr.io/kandlerli/home-agent@sha256:7302d35c2f2d8691d4bcf629703f0372575aa002d1b2c00a16d2e06b4a8c2b9f"

# Same reasoning as home_agent_image above -- update by hand after each
# meaningful build (see this repo's own build-sankey-export.yml
# workflow's "Print pushed image digest" step output -- unlike
# home_agent, this image's source/build live here, not in home-infra;
# see containers/sankey-export/ and that workflow's own comment).
sankey_export_image = "ghcr.io/kandlerli/sankey-export@sha256:bb43a6ee10d568affd3cbd1388af05a4bfe4274cd0880f3827fb2cb7f755e806"
