# node-exporter and kube-state-metrics for per-k3s-node visibility in the homeserver's Prometheus.

# A DaemonSet: one Pod per node, the runner node included. Its own privileged namespace: k3s-bootstrap's README, "Namespaces".
resource "kubernetes_daemon_set_v1" "node_exporter" {
  metadata {
    name      = "node-exporter"
    namespace = "node-exporter"
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

        # host_network: it reports the node's real stats, and Prometheus outside the cluster reaches it directly.
        host_network = true
        host_pid     = true
        dns_policy   = "ClusterFirstWithHostNet"

        security_context {
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name = "node-exporter"
          # Same image as home-infra's node_exporter, so metric names never diverge.
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

          # Runs as nobody, which can read everything it needs.
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

# kube-state-metrics: cluster object state that the exporters can't see.
resource "kubernetes_deployment_v1" "kube_state_metrics" {
  metadata {
    name      = "kube-state-metrics"
    namespace = "monitoring"
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
        # Pre-created in k3s-bootstrap.
        service_account_name = "kube-state-metrics"

        security_context {
          seccomp_profile {
            type = "RuntimeDefault"
          }
        }

        container {
          name  = "kube-state-metrics"
          image = "registry.k8s.io/kube-state-metrics/kube-state-metrics:v2.20.0@sha256:01171220c7c059afc85034ffe687bfe7249e41c0cc46fbe9a5128503ceee3016"

          # Only what the view ClusterRole grants; the image's defaults would spam failed lists.
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

          # 65534, the image's non-root default.
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

# LoadBalancer, so the homeserver's Prometheus can scrape it.
resource "kubernetes_service_v1" "kube_state_metrics" {
  metadata {
    name      = "kube-state-metrics-svc"
    namespace = "monitoring"
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
