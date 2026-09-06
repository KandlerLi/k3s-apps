# home_agent_image isn't a secret -- just a pinned public digest string
# (the private part is home_agent_ghcr_token, which authenticates the
# pull; this value alone doesn't grant access to anything). Tracked
# here instead of passed via TF_VAR so `terraform plan`/`apply` pick it
# up automatically -- update by hand after each meaningful build (see
# home-infra's build-home-agent.yml workflow's "Print pushed image
# digest" step output).
home_agent_image = "ghcr.io/kandlerli/home-agent@sha256:9682debdbde477e11b0a907838582656ed7bb3f78bbc03121abc1ea48b21e0ce"

# Same reasoning as home_agent_image above -- update by hand after each
# meaningful build (see home-infra's build-sankey-export.yml workflow's
# own "Print pushed image digest" step output).
sankey_export_image = "ghcr.io/kandlerli/sankey-export@sha256:c635edeaedfb6ac9628d3a7a11785f1adda23a1368d46751ddae1905b46b7f2a"
