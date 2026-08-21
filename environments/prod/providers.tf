provider "aws" {
  region = var.region
  # null (not "") when unset: an empty-string profile argument still makes
  # the AWS SDK look up a profile named "" and fail. CI has no local
  # profile at all -- it authenticates via OIDC-issued env credentials.
  profile = var.profile != "" ? var.profile : null
  default_tags {
    tags = {
      Project     = "effective-sia-spoon"
      Environment = "prod"
      ManagedBy   = "terraform"
    }
  }
}
