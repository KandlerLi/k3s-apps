# Small, disposable, k3s-owned PVC for /letsencrypt/acme.json --
# losing it means re-issuing every certificate, a real Let's Encrypt
# rate-limit risk. wait_until_bound = false: local-path's
# WaitForFirstConsumer binding mode means this only binds once a Pod
# references it, but Terraform creates it first -- waiting here would
# hang forever. Shape lives in modules/pvc_local_path.
moved {
  from = kubernetes_persistent_volume_claim_v1.ingress_acme
  to   = module.ingress_acme.kubernetes_persistent_volume_claim_v1.this
}

module "ingress_acme" {
  source = "../pvc_local_path"

  name = "ingress-acme"
  size = "128Mi"
}
