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
    # Pre-1.0 community provider: exact pin, bumped deliberately after reading its changelog.
    stalwart = {
      source  = "tahacodes/stalwart"
      version = "0.2.4"
    }
  }

  # CI applies this root, so state lives in the shared S3 bucket.
  backend "s3" {
    bucket       = "jkandler-terraform-state"
    key          = "k3s-apps/terraform.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}
