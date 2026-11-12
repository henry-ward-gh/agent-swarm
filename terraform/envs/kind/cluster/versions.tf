terraform {
  required_version = ">= 1.11"

  required_providers {
    kind = {
      source  = "tehcyx/kind"
      version = "~> 0.13.0"
    }
  }

  # State is as disposable as the kind cluster it describes (ADR 0004).
  backend "local" {}
}
