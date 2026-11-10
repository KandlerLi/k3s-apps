# SQLite, so local-path rather than NFS; this pins the Pod to the node the volume lands on.
module "vaultwarden_data" {
  source = "../pvc_local_path"

  name      = "vaultwarden-data"
  namespace = "apps"
  size      = "1Gi"
}
