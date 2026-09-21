terraform {
  required_providers {
    # Not a hashicorp/* provider, so it must be declared here too --
    # a module without this looks for hashicorp/stalwart and fails.
    stalwart = {
      source  = "tahacodes/stalwart"
      version = "0.2.4"
    }
  }
}
