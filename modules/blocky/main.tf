# Phase [Blocky migration] -- the last "LAN-facing, can't reach the
# isolated k3s VM" service to move, made viable by the same
# k3s_ingress_forward DNAT relay modules/ingress already uses (see
# home-infra's own role, extended to carry UDP+TCP DNS traffic too,
# not just HTTP/S). Router config never changes: the FRITZ!Box/DHCP
# setup keeps pointing LAN clients at the homeserver's own LAN IP for
# DNS exactly as it does today, and the homeserver relays port 53
# straight through to this Service instead of answering it directly.
#
# Blocky and Postgres share one Pod, not two -- the most faithful
# translation of the Docker deployment's own network_mode: host
# (Blocky's own queryLog.target still connects via 127.0.0.1, which a
# shared Pod network namespace reproduces exactly, no config changes
# needed there). Unlike the Docker version, Blocky's own DNS/HTTP
# ports don't need to bind a specific host IP any more -- external
# reachability is controlled entirely by the Service + DNAT relay now,
# not by which interface Blocky binds inside its own Pod. Postgres
# itself binds 0.0.0.0, not loopback-only -- see its own init_container
# block below for why that's required, not a relaxation.
#
# Blocky's own image declares USER 100 (confirmed directly against the
# GHCR registry's own image config, not assumed) -- security_context
# mirrors that exactly, plus the same cap_drop: ALL + NET_BIND_SERVICE
# the Docker deployment already used to bind port 53 as a non-root
# user. Postgres gets no forced security_context at all, matching the
# Docker deployment's own deliberate exception: the official image's
# entrypoint needs to start as root to initialize/chown its own data
# directory on first run (same class of exception as modules/ingress's
# own reasoning never needed, since Traefik doesn't own persistent
# state the way a database does).

resource "kubernetes_deployment_v1" "blocky" {
  metadata {
    name = "blocky"
  }

  spec {
    replicas = 1

    # Confirmed live (2026-09-01): the default RollingUpdate strategy
    # -- maxUnavailable rounding to 0 at replicas=1 -- creates the new
    # Pod before terminating the old one. Both land on the same node,
    # and the PVC below uses local-path (a hostPath wrapper with no
    # real CSI attach/detach exclusivity, unlike a genuine
    # ReadWriteOnce-enforcing driver), so both Pods' Postgres sidecars
    # briefly mounted the exact same underlying data directory at
    # once -- two concurrent, uncoordinated postgres processes writing
    # to the same files, which corrupted the WAL ("invalid record
    # length") and lost the log_entries table entirely, more than
    # once. Recreate guarantees the old Pod (and its data directory
    # lock) is fully gone before a new one starts.
    strategy {
      type = "Recreate"
    }

    selector {
      match_labels = {
        app = "blocky"
      }
    }

    template {
      metadata {
        labels = {
          app = "blocky"
        }
      }

      spec {
        # Neither container talks to the Kubernetes API.
        automount_service_account_token = false

        container {
          name  = "blocky"
          image = "ghcr.io/0xerr0r/blocky:v0.34.0@sha256:595136fb127f4c952b621113e668c09acdcf15ac054d96ee6d4c51a76c35f5fd"

          port {
            name           = "dns-tcp"
            container_port = 53
            protocol       = "TCP"
          }
          port {
            name           = "dns-udp"
            container_port = 53
            protocol       = "UDP"
          }
          port {
            name           = "http"
            container_port = 4000
          }

          resources {
            requests = {
              cpu    = "20m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "256Mi"
            }
          }

          security_context {
            read_only_root_filesystem  = true
            allow_privilege_escalation = false
            run_as_non_root            = true
            run_as_user                = 100
            capabilities {
              drop = ["ALL"]
              add  = ["NET_BIND_SERVICE"]
            }
          }

          volume_mount {
            name       = "config"
            mount_path = "/app/config.yml"
            sub_path   = "config.yml"
            read_only  = true
          }
          volume_mount {
            name       = "tmp"
            mount_path = "/tmp"
          }

          # Blocky's own image is FROM scratch -- no shell, confirmed
          # against home-infra's own role (docker exec blocky sh fails
          # with "executable file not found"). Its own binary ships a
          # "healthcheck" subcommand for exactly this reason. Unlike
          # the Docker deployment, no --bindip/--port override is
          # needed -- that was only required there because Blocky was
          # bound to the homeserver's own real LAN IP, not 127.0.0.1;
          # here it binds 0.0.0.0, so the healthcheck's own default
          # (dial 127.0.0.1:53) matches correctly on its own.
          readiness_probe {
            exec {
              command = ["/app/blocky", "healthcheck"]
            }
            initial_delay_seconds = 5
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 5
          }
          liveness_probe {
            exec {
              command = ["/app/blocky", "healthcheck"]
            }
            initial_delay_seconds = 15
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 5
          }
        }

        # A native sidecar (restart_policy = "Always" on an
        # init_container -- KEP-753, GA), not a regular container.
        # Confirmed live (2026-09-01): as two ordinary containers with
        # no ordering guarantee between them, Blocky started fast
        # enough to attempt its own Postgres connection *before*
        # Postgres finished its one-time initdb (data page checksums,
        # subdirectories, bootstrap script -- genuinely several
        # seconds on first run), exhausted its own fixed 3-attempt
        # retry budget, and permanently fell back to console-only
        # query logging for that Pod's entire lifetime -- Blocky never
        # retries the writer again afterward, so the query_log table
        # was never even created, and Grafana's own blocky-postgres
        # dashboard stayed empty. A native sidecar starts before the
        # Pod's main containers and blocks them from starting at all
        # until its own readiness_probe below first succeeds, removing
        # the race entirely rather than just tolerating it faster.
        init_container {
          name  = "postgres"
          image = "postgres:17-alpine@sha256:18cfe3ef5e6815560c98237d6216d1e5119702fb0f3894c8785dd58b8bbe5d73"

          restart_policy = "Always"

          port {
            name           = "postgres"
            container_port = 5432
          }

          env_from {
            secret_ref {
              name = kubernetes_secret_v1.blocky_postgres_credentials.metadata[0].name
            }
          }

          # 0.0.0.0, not 127.0.0.1 -- confirmed live (2026-09-01):
          # loopback-only broke the exact thing blocky-svc's own
          # postgres port exists for. A Kubernetes Service is not a
          # network namespace trick; it DNATs to the Pod's real IP,
          # which nothing outside this Pod can ever reach if Postgres
          # only listens on 127.0.0.1 -- Grafana got a flat "connection
          # refused" on every query. The access boundary here is
          # correctly the Service's own scope (only reachable from
          # inside the cluster, same as every other backend this
          # module or modules/grafana talks to) plus the official
          # image's own password-required pg_hba.conf default, not
          # which interface postgres itself binds -- Blocky's own
          # connection over 127.0.0.1 (this Pod's shared network
          # namespace) keeps working unchanged either way.
          #
          # args, not command: Kubernetes' own container.command
          # replaces the image's ENTRYPOINT (Docker's docker-
          # entrypoint.sh), not just its CMD. That entrypoint is what
          # initializes/chowns the data directory on first run and
          # drops privileges from root to the postgres user before
          # actually exec'ing the server -- skipping it (confirmed
          # live, 2026-09-01) starts the postgres binary directly as
          # root, which it refuses outright ('"root" execution of the
          # PostgreSQL server is not permitted'). args leaves the
          # entrypoint in charge and passes this flag through to it,
          # the same way `docker run postgres -c listen_addresses=...`
          # does.
          args = ["-c", "listen_addresses=0.0.0.0"]

          resources {
            requests = {
              cpu    = "20m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "500m"
              memory = "256Mi"
            }
          }

          volume_mount {
            name       = "postgres-data"
            mount_path = "/var/lib/postgresql/data"
          }

          readiness_probe {
            exec {
              command = ["pg_isready", "-U", "blocky", "-d", "blocky_query_log"]
            }
            initial_delay_seconds = 10
            period_seconds        = 10
            timeout_seconds       = 5
            failure_threshold     = 5
          }
          liveness_probe {
            exec {
              command = ["pg_isready", "-U", "blocky", "-d", "blocky_query_log"]
            }
            initial_delay_seconds = 20
            period_seconds        = 30
            timeout_seconds       = 5
            failure_threshold     = 5
          }
        }

        volume {
          name = "config"
          secret {
            secret_name = kubernetes_secret_v1.blocky_config.metadata[0].name
          }
        }
        volume {
          name = "tmp"
          empty_dir {
            medium     = "Memory"
            size_limit = "16Mi"
          }
        }
        volume {
          name = "postgres-data"
          persistent_volume_claim {
            claim_name = kubernetes_persistent_volume_claim_v1.blocky_postgres.metadata[0].name
          }
        }
      }
    }
  }
}

# type = LoadBalancer, matching modules/deluge's own dual-protocol
# deluge-peer-svc precedent for the DNS ports -- k3s's bundled
# ServiceLB binds this directly to k3s-node-1's own address, giving
# home-infra's own k3s_ingress_forward role a stable
# 192.168.101.10:53 (tcp+udp) DNAT target. postgres/http don't need
# DNAT (Grafana/Prometheus reach this address directly -- the
# homeserver and every other in-cluster Pod already have a route into
# the k3s VM's own isolated network, unlike LAN clients or the public
# internet), but ride along on the same Service since a single stable
# address is simplest for all four ports together.
resource "kubernetes_service_v1" "blocky" {
  metadata {
    name = "blocky-svc"
  }

  wait_for_load_balancer = false

  spec {
    type = "LoadBalancer"
    # Confirmed live (2026-09-01), the moment real LAN DNS traffic
    # started flowing through k3s_ingress_forward's own DNAT relay:
    # kube-proxy's default externalTrafficPolicy (Cluster) masquerades
    # the original client's source IP when routing Service traffic to
    # a Pod, replacing it with a cluster-internal address (10.42.0.1)
    # before Blocky ever sees it -- its own query log lost every real
    # LAN client's identity, the exact thing that log exists to
    # capture. Local is safe here specifically because Blocky's own
    # Pod and this Service's LoadBalancer IP are both pinned to
    # k3s-node-1 (single replica, no node_selector needed elsewhere in
    # this module) -- no risk of dropping traffic that arrived at a
    # node with no local endpoint, the one real tradeoff Local usually
    # carries.
    external_traffic_policy = "Local"

    selector = {
      app = "blocky"
    }

    port {
      name        = "dns-tcp"
      protocol    = "TCP"
      port        = 53
      target_port = 53
    }
    port {
      name        = "dns-udp"
      protocol    = "UDP"
      port        = 53
      target_port = 53
    }
    port {
      name        = "http"
      port        = 4000
      target_port = 4000
    }
    port {
      name        = "postgres"
      port        = 5432
      target_port = 5432
    }
  }
}
