# Phase B of moving github_runner to k3s (see the approved plan in
# home-infra's own plan history): one Deployment per repository in
# var.github_runner_repositories, via for_each -- the first use of
# for_each in this repo. Every other module here is "one module per
# distinct service"; this is a data-driven multiplication of *one*
# service instead, so it earns the exception rather than following
# that convention.
#
# Also the first use of node_selector/toleration anywhere in this repo
# (or home-infra) -- every Deployment here is pinned to k3s-node-2 and
# tolerates its ci=github-runner:NoSchedule taint, the second, tainted
# k3s node ansible/roles/k3s_node now supports specifically so CI
# workloads never compete with, or endanger, anything on k3s-node-1.
#
# Docker access: a privileged docker:dind sidecar per Pod, not
# kaniko/rootless building -- a deliberate, accepted trade-off (see the
# plan): every repository's existing `docker build`/`docker run`
# workflow steps keep working completely unmodified, at the real cost
# that a privileged container can escape to its own node. Contained to
# k3s-node-2 alone, which runs nothing else. The two containers share
# a Pod network namespace (an ordinary Kubernetes property, not
# anything configured here), so the runner container reaches the
# sidecar over plain localhost TCP -- DOCKER_TLS_CERTDIR="" disables
# TLS entirely on the dind side, which is fine specifically because
# that traffic never leaves the Pod's own network namespace.
#
# Runner image: the community myoung34/github-runner image, not a
# hand-rolled entrypoint -- its own registration/deregistration logic
# (on container start/stop) replaces the drift/busy-safety Ansible
# asserts in home-infra's configure_repository.yml, which exist
# specifically because that's a *persistent* systemd service Ansible
# reapplies idempotently; a Kubernetes Deployment restarting a Pod
# doesn't have that problem. debian-trixie variant, matching every
# other Debian image pinned elsewhere in this project.
#
# Resources: not yet measured from real usage (first deploy) -- sized
# off the old VM's own proven real-world capacity instead of a guess:
# it already runs all of today's repositories as systemd processes on
# the same 2 vCPU/2048Mi budget k3s-node-2 itself has. Burstable
# (requests small, limits generous) since jobs are occasional/bursty,
# not constantly running -- revisit against real usage once live,
# matching this project's own measure-then-size discipline everywhere
# else there's already real data to size from.

locals {
  github_runner_repositories_by_id = {
    for repo in var.github_runner_repositories : repo.id => repo
  }
}

resource "kubernetes_deployment_v1" "github_runner" {
  for_each = local.github_runner_repositories_by_id

  metadata {
    name = "github-runner-${each.key}"
  }

  spec {
    replicas = 1

    selector {
      match_labels = {
        app = "github-runner-${each.key}"
      }
    }

    template {
      metadata {
        labels = {
          app = "github-runner-${each.key}"
        }
      }

      spec {
        # Neither container talks to the Kubernetes API.
        automount_service_account_token = false

        node_selector = {
          "kubernetes.io/hostname" = "k3s-node-2"
        }

        toleration {
          key      = "ci"
          operator = "Equal"
          value    = "github-runner"
          effect   = "NoSchedule"
        }

        container {
          name  = "runner"
          image = "myoung34/github-runner:2.337.0-debian-trixie@sha256:ab5c1f5abd6e96fa357c5003575a6b431265d5e7a41d81b5ec690abf3163dad7"

          env {
            name = "ACCESS_TOKEN"
            value_from {
              secret_key_ref {
                name = kubernetes_secret_v1.github_runner_token.metadata[0].name
                key  = "token"
              }
            }
          }
          env {
            name  = "REPO_URL"
            value = "https://github.com/${var.github_runner_owner}/${each.value.repository}"
          }
          env {
            name  = "RUNNER_SCOPE"
            value = "repo"
          }
          # k3s-node-2-<id>, not <id> alone -- distinct from the old VM's
          # own github-runner-<id> names so both can register and serve
          # side by side during the additive rollout (Phase C), and so
          # it's obvious from GitHub's own runner list which one picked
          # up a given job.
          env {
            name  = "RUNNER_NAME"
            value = "k3s-node-2-${each.key}"
          }
          # Matches today's real labels exactly, so every repository's
          # existing runs-on: [self-hosted, home, debian] selector keeps
          # working unmodified -- this is what makes the rollout
          # additive rather than requiring a workflow-file change per
          # repository.
          env {
            name  = "LABELS"
            value = "home,debian,x64"
          }
          # Persistent, not autoscaled-ephemeral -- matches today's real
          # shape (one long-lived process per repository), the smallest
          # change from the proven VM-based design.
          env {
            name  = "EPHEMERAL"
            value = "false"
          }
          # The image itself should be bumped to update the runner
          # binary, not have it silently self-update inside a running
          # container -- same reasoning as the old role's own
          # --disableupdate config.sh flag.
          env {
            name  = "DISABLE_AUTO_UPDATE"
            value = "true"
          }
          # This image can also start its own embedded dockerd -- never
          # here, the dind sidecar below owns that entirely.
          env {
            name  = "START_DOCKER_SERVICE"
            value = "false"
          }
          env {
            name  = "DOCKER_HOST"
            value = "tcp://localhost:2375"
          }

          # No read_only_root_filesystem/non-root here (unlike most
          # other modules' containers) -- this container's filesystem is
          # the real CI job's own working directory; checkout, package
          # installs, and arbitrary workflow steps all need to write to
          # it, the same reason home-infra's own per-repo service
          # accounts were never given a restricted shell either.
          resources {
            requests = {
              cpu    = "10m"
              memory = "64Mi"
            }
            limits = {
              cpu    = "200m"
              memory = "256Mi"
            }
          }
        }

        container {
          name  = "dind"
          image = "docker:29.7.2-dind@sha256:12e683a161823b2a839aeea999b9d960e6e1f9a97b1679ad6b441982e2d9cf07"

          env {
            name  = "DOCKER_TLS_CERTDIR"
            value = ""
          }

          security_context {
            privileged = true
          }

          resources {
            requests = {
              cpu    = "50m"
              memory = "128Mi"
            }
            limits = {
              cpu    = "1000m"
              memory = "768Mi"
            }
          }

          # Avoids overlayfs-on-overlayfs (this container's own writable
          # layer already is one) for everything a real docker build
          # actually writes -- a plain emptyDir, not a PVC: build cache
          # losing itself on a Pod restart is a performance hit, not
          # data loss, the same "starting fresh is low-stakes" reasoning
          # modules/alertmanager's own no-PVC decision used.
          volume_mount {
            name       = "docker-data"
            mount_path = "/var/lib/docker"
          }
        }

        volume {
          name = "docker-data"
          empty_dir {}
        }
      }
    }
  }
}
