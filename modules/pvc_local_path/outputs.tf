output "name" {
  value = kubernetes_persistent_volume_claim_v1.this.metadata[0].name
}
