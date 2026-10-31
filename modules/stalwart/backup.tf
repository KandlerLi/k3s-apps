# Nightly copy of Stalwart's RocksDB to the red HDD. RocksDB is only consistent while Stalwart is stopped,
# so the job scales it to 0 and always back to 1. home-infra's stalwart_backup role owns the destination.

resource "kubernetes_persistent_volume_claim_v1" "stalwart_backup" {
  metadata {
    name      = "stalwart-backup"
    namespace = "apps"
  }

  spec {
    access_modes       = ["ReadWriteMany"]
    storage_class_name = "local-path"
    volume_name        = "stalwart-backup-pv"

    resources {
      requests = {
        storage = "20Gi"
      }
    }
  }
}

resource "kubernetes_cron_job_v1" "stalwart_backup" {
  metadata {
    name      = "stalwart-backup"
    namespace = "apps"
  }

  spec {
    # Before authelia-backup (03:45) and paperless-export (04:15), so the backups don't overlap.
    schedule                      = "15 3 * * *"
    concurrency_policy            = "Forbid"
    starting_deadline_seconds     = 300
    successful_jobs_history_limit = 3
    failed_jobs_history_limit     = 3

    job_template {
      metadata {}

      spec {
        # A retry would stop Stalwart a second time; the StalwartDown alert and the freshness check cover a failure.
        backoff_limit           = 0
        active_deadline_seconds = 600

        template {
          metadata {
            labels = {
              app = "stalwart-backup"
            }
          }

          spec {
            restart_policy = "Never"
            # k3s-bootstrap's stalwart-backup: may only scale the stalwart Deployment and list Pods.
            service_account_name            = "stalwart-backup"
            automount_service_account_token = true

            security_context {
              # The provider otherwise sends false, which the restricted level rejects.
              run_as_non_root = true

              seccomp_profile {
                type = "RuntimeDefault"
              }
            }

            container {
              name  = "stalwart-backup"
              image = "python:3.13-alpine@sha256:7415fbc3c9e4979cc717d92377ab2bc7b2b4a2af1ac03cc52b5f3f88efedaf3a"

              command = ["python3", "-c", local.stalwart_backup_script]

              resources {
                requests = {
                  memory = "32Mi"
                  cpu    = "10m"
                }
                limits = {
                  memory = "256Mi"
                  cpu    = "500m"
                }
              }

              # Must match home-infra's stalwart_backup account, so root_squash writes as the export's owner.
              security_context {
                read_only_root_filesystem  = true
                allow_privilege_escalation = false
                run_as_non_root            = true
                run_as_user                = 982
                run_as_group               = 977
                capabilities {
                  drop = ["ALL"]
                }
              }

              volume_mount {
                name       = "stalwart-data"
                mount_path = "/stalwart"
                read_only  = true
              }
              volume_mount {
                name       = "stalwart-backup"
                mount_path = "/backup"
              }
            }

            volume {
              name = "stalwart-data"
              persistent_volume_claim {
                claim_name = kubernetes_persistent_volume_claim_v1.stalwart.metadata[0].name
                read_only  = true
              }
            }
            volume {
              name = "stalwart-backup"
              persistent_volume_claim {
                claim_name = kubernetes_persistent_volume_claim_v1.stalwart_backup.metadata[0].name
              }
            }
          }
        }
      }
    }
  }
}

locals {
  stalwart_backup_script = <<-PYTHON
    import glob
    import json
    import os
    import signal
    import ssl
    import sys
    import tarfile
    import time
    import urllib.request

    API = "https://kubernetes.default.svc"
    SA = "/var/run/secrets/kubernetes.io/serviceaccount"
    DEPLOYMENT = "/apis/apps/v1/namespaces/apps/deployments/stalwart/scale"
    # Only live Pods: a node shutdown leaves the old Pod behind as Succeeded/Failed until it's garbage-collected.
    PODS = "/api/v1/namespaces/apps/pods?labelSelector=app%3Dstalwart&fieldSelector=status.phase%21%3DSucceeded%2Cstatus.phase%21%3DFailed"
    DEST_DIR = "/backup"
    RETENTION_DAYS = 14

    # activeDeadlineSeconds sends SIGTERM; exiting through finally still scales Stalwart back up.
    signal.signal(signal.SIGTERM, lambda *_: sys.exit("terminated"))

    with open(f"{SA}/token") as f:
        token = f.read()
    tls = ssl.create_default_context(cafile=f"{SA}/ca.crt")


    def call(method, path, body=None):
        request = urllib.request.Request(
            API + path,
            method=method,
            data=json.dumps(body).encode() if body is not None else None,
            headers={"Authorization": f"Bearer {token}", "Content-Type": "application/merge-patch+json"},
        )
        with urllib.request.urlopen(request, context=tls, timeout=30) as response:
            return json.load(response)


    def scale(replicas):
        call("PATCH", DEPLOYMENT, {"spec": {"replicas": replicas}})


    date = time.strftime("%Y%m%d-%H%M%S")
    out_path = os.path.join(DEST_DIR, f"stalwart-{date}.tar.gz")
    partial = out_path + ".partial"

    try:
        scale(0)
        deadline = time.time() + 180
        while call("GET", PODS)["items"]:
            if time.time() > deadline:
                raise SystemExit("Stalwart's Pod didn't stop within 180 s")
            time.sleep(2)
        with tarfile.open(partial, "w:gz") as tar:
            tar.add("/stalwart", arcname="stalwart")
        os.replace(partial, out_path)
    finally:
        if os.path.exists(partial):
            os.remove(partial)
        scale(1)

    cutoff = time.time() - RETENTION_DAYS * 86400
    for old in glob.glob(os.path.join(DEST_DIR, "stalwart-*.tar.gz")):
        if os.path.getmtime(old) < cutoff:
            os.remove(old)

    print(f"Stalwart backup written: {out_path} ({os.path.getsize(out_path) // 1048576} MiB)")
    PYTHON
}
