# acme.json: losing it means re-issuing every certificate.
moved {
  from = kubernetes_persistent_volume_claim_v1.ingress_acme
  to   = module.ingress_acme.kubernetes_persistent_volume_claim_v1.this
}

module "ingress_acme" {
  source = "../pvc_local_path"

  name = "ingress-acme"
  size = "128Mi"
}
