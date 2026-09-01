# Blocky's own config.yml embeds the Postgres password directly in
# queryLog.target's connection string (postgres://user:PASSWORD@...) --
# unlike Traefik's own usersFile indirection, Blocky has no separate
# credentials-file mechanism for this, so the whole file is
# credential-bearing and belongs in a Secret, never a ConfigMap. Same
# no_log treatment home-infra's own config.yml.j2 task already gives
# it.
#
# Mirrors home-infra's own templates/config.yml.j2 nearly verbatim,
# every conditional resolved to its live-true branch (there's only one
# denylist group configured today, "ads") -- the same lowest-risk
# translation discipline modules/ingress used. ports.dns/ports.http
# bind 0.0.0.0 here, not a specific host IP the way the Docker
# deployment had to (blocky_bind_address, the homeserver's own real
# LAN IP) -- external reachability is controlled by the Service +
# home-infra's own k3s_ingress_forward DNAT relay now, not by which
# interface Blocky itself binds inside its own Pod.
resource "kubernetes_secret_v1" "blocky_config" {
  metadata {
    name = "blocky-config"
  }

  data = {
    "config.yml" = <<-EOT
      upstreams:
        groups:
          default:
            - 1.1.1.1
            - 9.9.9.9

      bootstrapDns:
        - upstream: 1.1.1.1
        - upstream: 9.9.9.9

      ports:
        dns: 0.0.0.0:53
        http: 0.0.0.0:4000

      prometheus:
        enable: true
        path: /metrics

      blocking:
        denylists:
          ads:
            - https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts
        clientGroupsBlock:
          default:
            - ads

      queryLog:
        type: postgresql
        target: postgres://blocky:${var.blocky_postgres_password}@127.0.0.1:5432/blocky_query_log?sslmode=disable
        logRetentionDays: 7
        flushInterval: 30s
    EOT
  }

  type = "Opaque"
}

# Postgres's own credentials, read via env vars by the postgres
# container below -- separate from the config.yml Secret above since
# these two Secrets have different consumers (Postgres itself vs.
# Blocky reading its own connection string).
resource "kubernetes_secret_v1" "blocky_postgres_credentials" {
  metadata {
    name = "blocky-postgres-credentials"
  }

  data = {
    POSTGRES_USER     = "blocky"
    POSTGRES_PASSWORD = var.blocky_postgres_password
    POSTGRES_DB       = "blocky_query_log"
  }

  type = "Opaque"
}
