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
# k3s-node-2 alone, which runs nothing else. Reached over a shared
# Unix socket volume (`/var/run/docker.sock`, an emptyDir mounted at
# the identical path in both containers), not TCP -- confirmed live
# that docker:dind's own entrypoint never actually opens a TCP
# listener just because DOCKER_TLS_CERTDIR="" is set (that only skips
# TLS cert generation); the socket is the only thing it ever binds,
# matching the officially-documented host-socket pattern, just shared
# between two containers in one Pod instead of between a container and
# its host.
#
# Confirmed live and fixed: any job step using GitHub Actions' own
# `container:` job option (every repository's own Validate job, home-
# infra's own checks.yml included) failed with "stat /__e/node24/bin/
# node: no such file or directory" -- actions/runner bind-mounts its
# own /actions-runner/externals (the Node.js runtime for JS-based
# actions) and /_work into the job containers it asks Docker to start,
# and Docker resolves a bind-mount's *source* path against the
# *daemon's* own filesystem, not the client's. With the daemon living
# in a separate dind container, those paths simply didn't exist there.
# Same root cause the image's own upstream docs call out for the
# host-socket case ("this path needs to be the same path on host and
# inside the container") -- just not documented for a separate-sidecar
# dind setup at all. Fixed by sharing both directories as real
# volumes, mounted at the identical absolute path in both containers,
# so the daemon's own filesystem view actually has the files being
# bind-mounted. /actions-runner is baked into the runner image's own
# layer (not empty at start), so a plain empty_dir mounted there would
# shadow the real install -- seeded first by a same-image init
# container instead, the same "seed a volume from image content before
# the real container mounts shift it" shape modules/deluge's own
# seed-web-conf init container already established in this repo.
#
# Confirmed live and fixed: a `container:` job step still got EACCES
# writing into the shared "work" volume even after the bind-mount fix
# above. Root cause is one level deeper than this Pod's own internal
# identity: GitHub Actions' own workflow shape here captures id -u/
# id -g from the "Build CI image" job and passes it as `container:
# options: --user <uid>:<gid>` to the separate "Validate" job -- true
# by construction on the old VM (one shared filesystem, one real
# account), no longer guaranteed once this module's own runners pool
# additively alongside it: confirmed live, a run where "Build CI
# image" executed on the *old* VM (capturing its own real ghr-<id>
# system account's uid) while "Validate" landed on this module's own
# runner, asking to write as a uid that means nothing here. No fix on
# this Pod's own side can predict or match an arbitrary incoming uid
# from a different machine, so /work is kept world-writable
# continuously instead, by a dedicated permission-fixer container (not
# folded into dind's own command -- tried that first, and it left a
# second, confusingly-orphaned copy of the whole command running as a
# child of docker-init instead of cleanly replacing the entrypoint;
# a separate container sidesteps the exec/subshell complexity
# entirely). Continuous, not one-shot, since this image's own
# entrypoint creates fresh restrictive-mode subdirectories on every
# job cycle, not just at Pod start.
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

        # Seeds the shared actions-runner-install volume from this same
        # image's own baked-in /actions-runner before either main
        # container starts -- see the header comment above for why this
        # needs to be real, shared, non-empty content rather than a
        # plain empty_dir mounted straight over the image's own install.
        init_container {
          name    = "seed-runner-install"
          image   = "myoung34/github-runner:2.337.0-debian-trixie@sha256:ab5c1f5abd6e96fa357c5003575a6b431265d5e7a41d81b5ec690abf3163dad7"
          command = ["sh", "-c", "cp -a /actions-runner/. /actions-runner-shared/"]

          volume_mount {
            name       = "actions-runner-install"
            mount_path = "/actions-runner-shared"
          }
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
          # Ephemeral, deliberately -- one job per Pod, then it exits
          # and the Deployment restarts it fresh for the next. Confirmed
          # live: the entrypoint's own EPHEMERAL check is `[ -n
          # "${EPHEMERAL}" ]`, true for ANY set value including
          # "false" -- there's no way to opt out of ephemeral mode by
          # setting this to a falsy string, only by leaving it unset
          # entirely, so it's set to "true" here to make the real,
          # already-live behavior explicit rather than accidental. A
          # deliberate departure from the old VM-based role's own
          # persistent-systemd-service shape: ephemeral is GitHub's own
          # recommended pattern for container/k8s-hosted runners, and it
          # sidesteps the whole class of cross-job workspace-reuse bug
          # that role needs real Ansible logic to handle (root-owned
          # leftover files from a containerized job step blocking a
          # later job's own checkout) -- every Pod starts clean.
          env {
            name  = "EPHEMERAL"
            value = "true"
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
          # Keeps this container's own Runner.Listener process as uid 0
          # rather than gosu-ing to an internal non-root account -- one
          # less source of identity mismatch for the case where a
          # workflow's own jobs all land on this same Pod (see the
          # permission-fixer container's own comment for the case where
          # they don't).
          env {
            name  = "RUN_AS_ROOT"
            value = "true"
          }
          # The shared socket volume below, not TCP -- see this file's
          # own header comment for why.
          env {
            name  = "DOCKER_HOST"
            value = "unix:///var/run/docker.sock"
          }
          # A plain, explicit path rather than this image's own
          # /_work/<runner-name> default -- both containers mount the
          # shared "work" volume at this exact path (see the header
          # comment on why it has to be identical on both sides).
          env {
            name  = "RUNNER_WORKDIR"
            value = "/work"
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

          volume_mount {
            name       = "actions-runner-install"
            mount_path = "/actions-runner"
          }
          volume_mount {
            name       = "work"
            mount_path = "/work"
          }
          volume_mount {
            name       = "docker-socket"
            mount_path = "/var/run"
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
          # Same two paths, same absolute mount points as the runner
          # container above -- this is what actually fixes the
          # container: job bind-mount failure: the daemon (this
          # container) now has the real files at the paths it's asked
          # to bind-mount from.
          volume_mount {
            name       = "actions-runner-install"
            mount_path = "/actions-runner"
          }
          volume_mount {
            name       = "work"
            mount_path = "/work"
          }
          # dockerd creates docker.sock here on startup -- shared with
          # the runner container above so it can reach it at the exact
          # same path, unix sockets aren't network-addressable.
          volume_mount {
            name       = "docker-socket"
            mount_path = "/var/run"
          }
        }

        # Keeps /work continuously world-writable -- see this file's
        # own header comment for why this can't just be fixed once at
        # startup, and why it needs to be a genuinely separate
        # container rather than folded into dind's own command. Reuses
        # the runner image (already being pulled twice over for the
        # init container and the runner container itself) rather than
        # introducing a third distinct image just for this.
        container {
          name    = "permission-fixer"
          image   = "myoung34/github-runner:2.337.0-debian-trixie@sha256:ab5c1f5abd6e96fa357c5003575a6b431265d5e7a41d81b5ec690abf3163dad7"
          command = ["sh", "-c", "while true; do chmod -R 0777 /work 2>/dev/null; sleep 2; done"]

          resources {
            requests = {
              cpu    = "5m"
              memory = "16Mi"
            }
            limits = {
              cpu    = "50m"
              memory = "32Mi"
            }
          }

          volume_mount {
            name       = "work"
            mount_path = "/work"
          }
        }

        volume {
          name = "docker-data"
          empty_dir {}
        }
        volume {
          name = "actions-runner-install"
          empty_dir {}
        }
        volume {
          name = "work"
          empty_dir {}
        }
        volume {
          name = "docker-socket"
          empty_dir {}
        }
      }
    }
  }
}
