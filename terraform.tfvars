# home_agent_image isn't a secret -- just a pinned public digest string
# (the private part is home_agent_ghcr_token, which authenticates the
# pull; this value alone doesn't grant access to anything). Tracked
# here instead of passed via TF_VAR so `terraform plan`/`apply` pick it
# up automatically. Each build of home-infra's build-home-agent.yml also
# pushes the :main tag, and Renovate proposes the new digest here.
home_agent_image = "ghcr.io/kandlerli/home-agent:main@sha256:4ed81690c46095f6730be6d5a1629314583f614b8f2ef17d0ba7b6bf8d06689e"

# Same as home_agent_image above, except this image's source and build
# (build-sankey-export.yml) live in this repo: containers/sankey-export/.
sankey_export_image = "ghcr.io/kandlerli/sankey-export:main@sha256:8edab0e2e19f8ac0d0756af7705cceb1c20de88692d4aa0719cd379f03b88bae"
