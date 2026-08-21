terraform {
  required_version = ">= 1.11"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    tls = {
      source  = "hashicorp/tls"
      version = "~> 4.0"
    }
  }

  # Deliberately no `backend` block: bootstrap uses local state, applied
  # manually once by an admin (design.md §1, "bootstrap/"). This avoids a
  # chicken-and-egg problem -- bootstrap creates the state bucket that
  # environments/prod's own remote backend depends on.
}

provider "aws" {
  region = var.region
  # null (not "") when unset: an empty-string profile argument still makes
  # the AWS SDK look up a profile named "" and fail. CI has no local
  # profile at all -- it authenticates via OIDC-issued env credentials.
  profile = var.profile != "" ? var.profile : null
}
