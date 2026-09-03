terraform {
  required_version = ">= 1.16.0"

  required_providers {
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 3.2"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.9"
    }
  }

  # Added 2026-09-03, alongside splitting modules/github_runner + the
  # cluster-scoped PVs out into their own root (its own separate S3
  # state, key k3s-bootstrap/terraform.tfstate -- originally a
  # bootstrap/ subdirectory of this same repo, later extracted into the
  # standalone k3s-bootstrap repo alongside repo-infra/terraform-state)
  # -- this root now gets applied by CI, which is ephemeral and can't
  # rely on a local state file the way the old fully-local setup could.
  # Same bucket, same convention every other repo in this workspace
  # already uses.
  backend "s3" {
    bucket       = "jkandler-terraform-state"
    key          = "k3s-apps/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
