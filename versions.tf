terraform {
  required_version = ">= 1.16.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 6.0"
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
