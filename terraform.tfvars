# home_agent_image isn't a secret -- just a pinned public digest string
# (the private part is home_agent_ghcr_token, which authenticates the
# pull; this value alone doesn't grant access to anything). Tracked
# here instead of passed via TF_VAR so `terraform plan`/`apply` pick it
# up automatically -- update by hand after each meaningful build (see
# home-infra's build-home-agent.yml workflow's "Print pushed image
# digest" step output).
home_agent_image = "ghcr.io/kandlerli/home-agent@sha256:a8d7507b05cedee9d339166472ad3cfb5ec4c26b6e7e5797d0c22613b3c37b60"

# Same reasoning as home_agent_image above -- update by hand after each
# meaningful build (see this repo's own build-sankey-export.yml
# workflow's "Print pushed image digest" step output -- unlike
# home_agent, this image's source/build live here, not in home-infra;
# see containers/sankey-export/ and that workflow's own comment).
sankey_export_image = "ghcr.io/kandlerli/sankey-export@sha256:bb43a6ee10d568affd3cbd1388af05a4bfe4274cd0880f3827fb2cb7f755e806"
