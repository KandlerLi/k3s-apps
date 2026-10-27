# A Secret: queryLog.target embeds the Postgres password.
resource "kubernetes_secret_v1" "blocky_config" {
  metadata {
    namespace = "apps"
    name      = "blocky-config"
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

# Postgres's own credentials, a separate consumer from config.yml.
resource "kubernetes_secret_v1" "blocky_postgres_credentials" {
  metadata {
    namespace = "apps"
    name      = "blocky-postgres-credentials"
  }

  data = {
    POSTGRES_USER     = "blocky"
    POSTGRES_PASSWORD = var.blocky_postgres_password
    POSTGRES_DB       = "blocky_query_log"
  }

  type = "Opaque"
}

# postgres_exporter needs a single DATA_SOURCE_NAME URI.
resource "kubernetes_secret_v1" "blocky_postgres_exporter_dsn" {
  metadata {
    namespace = "apps"
    name      = "blocky-postgres-exporter-dsn"
  }

  data = {
    DATA_SOURCE_NAME = "postgresql://blocky:${var.blocky_postgres_password}@127.0.0.1:5432/blocky_query_log?sslmode=disable"
  }

  type = "Opaque"
}
