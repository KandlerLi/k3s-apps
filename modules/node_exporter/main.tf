# Per-k3s-node resource visibility (BACKLOG.md's "Per-k3s-node Grafana
# dashboard + alerting"): before this module, the only Prometheus/
# Grafana visibility into this cluster was the *physical homeserver's*
# own node_exporter/cAdvisor (infra/home-infra's monitoring role) --
# `kubectl top nodes`/`kubectl describe node` were the only way to see
# either k3s node's own real CPU/mem/disk, which is exactly how a real
# drift (k3s-node-1 requesting 94% of its CPU budget while actually
# using 12%) went unnoticed until someone happened to check by hand.
#
# Two unrelated exporters share this one module rather than getting
# separate modules: node-exporter (this cluster's own OS-level host
# metrics, one Pod per node) and kube-state-metrics (Kubernetes object
# state -- resource *requests* vs what node-exporter/cAdvisor report as
# *actually used*, the exact request-vs-actual gap that motivated this
# module). They're always deployed and removed together for this
# workspace's own monitoring purposes, and neither is more than a
# couple resources on its own -- not worth splitting into two modules
# with no other reason to exist independently.
#
# Neither ServiceAccount here, nor the ClusterRoleBinding kube-state-
# metrics needs, live in this module -- see modules/kubernetes_dashboard's
# own main.tf comment for why granting RBAC has to happen in the
# separate k3s-bootstrap repo instead (this root's own CI ServiceAccount
# has no serviceaccounts/clusterrolebindings verb at all, deliberately).
# node-exporter itself needs no Kubernetes API access whatsoever (it
# only ever reads this node's own /proc, /sys, /), so it needs no
# ServiceAccount whatsoever, not even an unprivileged one.

# One Pod per node, unlike every other module in this repo (which pin a
# single replica to one specific node via node_selector) -- a DaemonSet
# is what actually makes that "one per node, including any future node"
# properly, rather than hand-maintaining a for_each over today's two
# node names. No node_selector here at all (the default: schedule onto
# every node), but it still needs this exact toleration to actually
# land on k3s-node-2 -- that node's own ci=github-runner:NoSchedule
# taint (ansible/roles/k3s_node, home-infra) exists specifically to
# keep ordinary Deployments off it, and a DaemonSet respects taints the
# same as anything else unless it tolerates them.
resource "kubernetes_daemon_set_v1" "node_exporter" {
  metadata {
    name = "node-exporter"
  }

  spec {
    selector {
      match_labels = {
        app = "node-exporter"
      }
    }

    template {
      metadata {
        labels = {
          app = "node-exporter"
        }
      }

      spec {
        automount_service_account_token = false

        toleration {
          key      = "ci"
          operator = "Equal"
          value    = "github-runner"
          effect   = "NoSchedule"
        }

        # host_network, not a Service -- node-exporter needs to report
        # this node's own real network/filesystem stats, not a Pod
        # sandbox's, and this is also what gives Prometheus (running
        # outside the cluster entirely, on the homeserver) a stable,
        # directly-reachable <node-ip>:9100 with no Service/Ingress
        # plumbing needed, the same "no Service needed, the host IP is
        # the address" shape home-infra's own node_exporter already
        # uses via network_mode: host. host_pid alongside it is the
        # image's own documented requirement for host_network mode
        # (some collectors need to see host-namespace process IDs to
        # attribute stats correctly).
        host_network = true
        host_pid     = true
        dns_policy   = "ClusterFirstWithHostNet"

        container {
          name = "node-exporter"
          # Same tag+digest as infra/home-infra's own
          # monitoring_node_exporter_image -- deliberately identical
          # across both the homeserver's and this cluster's copies, so
          # a metric name/label never differs between them for reasons
          # that have nothing to do with what's actually being measured.
          image = "prom/node-exporter:v1.12.1@sha256:1b4e4438faca4dd7e001dd445d161a4a2091b0fededa84093b3a8dfeae1f1be0"

          args = [
            "--path.procfs=/host/proc",
            "--path.sysfs=/host/sys",
            "--path.rootfs=/host/root",
            "--collector.filesystem.mount-points-exclude=^/(dev|proc|sys|host/root/(dev|proc|sys)($|/)).*",
          ]

          port {
            name           = "metrics"
            container_port = 9100
            host_port      = 9100
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "64Mi"
            }
          }

          # Not root, unlike the homeserver's own Docker copy (whose
          # own image default this repo doesn't control the same way)
          # -- the official image's nobody account (65534) can read
          # everything these three read-only mounts expose.
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            run_as_user                = 65534
            run_as_group               = 65534
            capabilities {
              drop = ["ALL"]
            }
          }

          volume_mount {
            name       = "proc"
            mount_path = "/host/proc"
            read_only  = true
          }
          volume_mount {
            name       = "sys"
            mount_path = "/host/sys"
            read_only  = true
          }
          volume_mount {
            name       = "root"
            mount_path = "/host/root"
            read_only  = true
          }
        }

        volume {
          name = "proc"
          host_path {
            path = "/proc"
          }
        }
        volume {
          name = "sys"
          host_path {
            path = "/sys"
          }
        }
        volume {
          name = "root"
          host_path {
            path = "/"
          }
        }
      }
    }
  }
}

# Cluster-wide object state (resource requests, replica counts, Pod
# phase, etc.) -- what node-exporter/cAdvisor can't see, since they
# only ever report real OS/container-runtime usage, never what the
# Kubernetes API itself thinks is requested/desired. A single replica
# (not a DaemonSet): this reads the whole cluster's own API state once
# per scrape, not any one node's local state, so more copies would only
# mean redundant API load, not more coverage.
resource "kubernetes_deployment_v1" "kube_state_metrics" {
  metadata {
    name = "kube-state-metrics"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "kube-state-metrics"
      }
    }

    template {
      metadata {
        labels = {
          app = "kube-state-metrics"
        }
      }

      spec {
        # Pre-created in k3s-bootstrap -- see this module's own header
        # comment. Referencing it here by name needs no RBAC grant over
        # the ServiceAccount object itself.
        service_account_name = "kube-state-metrics"

        container {
          name  = "kube-state-metrics"
          image = "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.20.0@sha256:01171220c7c059afc85034ffe687bfe7249e41c0cc46fbe9a5128503ceee3016"

          # Explicitly scoped to exactly what k3s-bootstrap's own
          # kube-state-metrics-view ClusterRoleBinding (bound to the
          # built-in "view" ClusterRole) actually grants -- the
          # upstream image's own default covers a few resources "view"
          # doesn't (e.g. ingressclasses, mutatingwebhookconfigurations),
          # which would otherwise silently fail to list and spam this
          # container's own logs. Secrets/configmaps deliberately left
          # out even though "view" would allow configmaps -- their
          # per-key metrics aren't needed for the request-vs-actual
          # dashboard this module exists for.
          args = [
            "--resources=cronjobs,daemonsets,deployments,jobs,namespaces,nodes,persistentvolumeclaims,persistentvolumes,pods,replicasets,services,statefulsets",
          ]

          port {
            name           = "metrics"
            container_port = 8080
          }

          resources {
            requests = {
              cpu    = "10m"
              memory = "32Mi"
            }
            limits = {
              cpu    = "100m"
              memory = "128Mi"
            }
          }

          # 65534 -- the image's own documented non-root default
          # (nobody), same as node-exporter above.
          security_context {
            allow_privilege_escalation = false
            read_only_root_filesystem  = true
            run_as_non_root            = true
            run_as_user                = 65534
            run_as_group               = 65534
            capabilities {
              drop = ["ALL"]
            }
          }

          liveness_probe {
            http_get {
              path = "/healthz"
              port = 8080
            }
            initial_delay_seconds = 5
            period_seconds        = 30
          }
        }
      }
    }
  }
}

# type = LoadBalancer, matching every other module here that needs to
# be reached from outside the cluster (Alertmanager, Blocky) -- k3s's
# bundled ServiceLB binds this directly to a node's own address, giving
# home-infra's own Prometheus a stable 192.168.101.10:8080 to scrape
# (see infra/home-infra's monitoring_k3s_kube_state_metrics_upstream).
# No external_traffic_policy override needed here, unlike Blocky's own
# Local policy -- this Service exists purely for Prometheus's own
# scrape requests, which don't care about preserving a real client's
# source IP the way Blocky's query log does.
resource "kubernetes_service_v1" "kube_state_metrics" {
  metadata {
    name = "kube-state-metrics-svc"
  }

  spec {
    type = "LoadBalancer"

    selector = {
      app = "kube-state-metrics"
    }

    port {
      port        = 8080
      target_port = 8080
    }
  }
}
