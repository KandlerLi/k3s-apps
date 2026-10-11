terraform {
  required_providers {
    # Not a hashicorp/* provider, so the module must declare it too.
    stalwart = {
      source  = "tahacodes/stalwart"
      version = "0.2.4"
    }
  }
}
