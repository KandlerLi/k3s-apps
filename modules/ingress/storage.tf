# A small dynamically-provisioned PVC for /letsencrypt/acme.json --
# unlike Alertmanager's/Grafana's own deliberate "start fresh, no PVC"
# choice, this one's own state is worth keeping across Pod restarts:
# losing it means re-issuing every certificate again, a real, avoidable
# Let's Encrypt rate-limit risk Traefik's own docs warn about
# explicitly. storage_class_name = "local-path" explicitly (not left
# unset) -- matching modules/deluge's own storage.tf finding that an
# unset/empty value gets serialized identically by this provider,
# confusing k3s's own DefaultStorageClass admission controller. Unlike
# Deluge's own NFS-backed, manually-paired PV/PVC (real, already-
# existing data), this is genuinely disposable, k3s-owned storage --
# a plain dynamically-provisioned PVC is enough, no manual PV needed.
# wait_until_bound = false: confirmed live this resource hangs
# indefinitely otherwise -- k3s's own local-path storage class uses
# WaitForFirstConsumer binding (the PVC only actually binds once a Pod
# references it), but Terraform creates this PVC *before* the
# Deployment that would do that (an implicit dependency via the volume
# reference), so waiting for it to reach Bound here is a genuine
# chicken-and-egg hang -- it can only bind after a later resource this
# same apply hasn't created yet.
#
# Shape lives in modules/pvc_local_path (extracted 2026-09-22,
# ponytail-audit -- see that module's own comment).
moved {
  from = kubernetes_persistent_volume_claim_v1.ingress_acme
  to   = module.ingress_acme.kubernetes_persistent_volume_claim_v1.this
}

module "ingress_acme" {
  source = "../pvc_local_path"

  name = "ingress-acme"
  size = "128Mi"
}
