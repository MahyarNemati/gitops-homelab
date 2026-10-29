terraform {
  required_version = ">= 1.9.0"

  required_providers {
    null = {
      source  = "hashicorp/null"
      version = "~> 3.2"
    }
    local = {
      source  = "hashicorp/local"
      version = "~> 2.5"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.6"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 3.3"
    }
  }

  # State is local by default so the repository is usable with no cloud
  # account. For anything shared, override with -backend-config: the token
  # below is in state, and local state in a git working tree is a mistake
  # waiting to happen.
  backend "local" {
    path = "terraform.tfstate"
  }
}
