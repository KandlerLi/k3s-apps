# home_agent_image isn't a secret -- just a pinned public digest string
# (the private part is home_agent_ghcr_token, which authenticates the
# pull; this value alone doesn't grant access to anything). Tracked
# here instead of passed via TF_VAR so `terraform plan`/`apply` pick it
# up automatically -- update by hand after each meaningful build (see
# home-infra's build-home-agent.yml workflow's "Print pushed image
# digest" step output).
home_agent_image = "ghcr.io/kandlerli/home-agent@sha256:0c26c979ff786b14c5044a3d70ea10526ac06253f5fb424596db4072e989013d"

# Same reasoning as home_agent_image above -- update by hand after each
# meaningful build (see this repo's own build-sankey-export.yml
# workflow's "Print pushed image digest" step output -- unlike
# home_agent, this image's source/build live here, not in home-infra;
# see containers/sankey-export/ and that workflow's own comment).
sankey_export_image = "ghcr.io/kandlerli/sankey-export@sha256:1df729d09e40440c1f92f06e292a3cd0a3db5802ce57de7d4db1a1c1958a2eca"
