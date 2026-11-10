# home_agent_image isn't a secret -- just a pinned public digest string
# (the private part is home_agent_ghcr_token, which authenticates the
# pull; this value alone doesn't grant access to anything). Tracked
# here instead of passed via TF_VAR so `terraform plan`/`apply` pick it
# up automatically. Each build of home-infra's build-home-agent.yml also
# pushes the :main tag, and Renovate proposes the new digest here.
home_agent_image = "ghcr.io/kandlerli/home-agent:main@sha256:9124434f328f51de4216d8f8aa2b69aa012c2c758678403834afb5fbdf9f9434"

# Same as home_agent_image above, except this image's source and build
# (build-sankey-export.yml) live in this repo: containers/sankey-export/.
sankey_export_image = "ghcr.io/kandlerli/sankey-export:main@sha256:0bde585edbd35c7313ba85e468e119b684e13a829b44adc9d567834ad6a95622"
