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
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
    }
    # Community provider (not HashiCorp's), pre-1.0, single maintainer --
    # pinned to an exact version on purpose: bump it deliberately after
    # reading its changelog, never via a ~> range.
    stalwart = {
      source  = "tahacodes/stalwart"
      version = "0.2.4"
    }
  }

  # CI applies this root, which is ephemeral and can't rely on a local
  # state file -- same bucket/convention every other repo here uses.
  backend "s3" {
    bucket       = "jkandler-terraform-state"
    key          = "k3s-apps/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
