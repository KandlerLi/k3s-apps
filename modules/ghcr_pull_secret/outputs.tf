output "name" {
  value = kubernetes_secret_v1.this.metadata[0].name
}
