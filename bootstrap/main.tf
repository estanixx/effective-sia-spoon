data "aws_caller_identity" "current" {}

locals {
  # Account-derived so the bucket name is never a second source of truth
  # (see design.md's "partial backend config" decision).
  state_bucket_name = "${var.name_prefix}-iac-tfstate-${data.aws_caller_identity.current.account_id}"

  # Role names are computed here (not read off the resources) so the
  # apply-role permissions boundary below can reference its own role's ARN
  # without an IAM-role/IAM-policy circular dependency.
  plan_role_name  = "${var.name_prefix}-plan"
  apply_role_name = "${var.name_prefix}-apply"

  plan_role_arn  = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.plan_role_name}"
  apply_role_arn = "arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/${local.apply_role_name}"
}

# --- Terraform state bucket -------------------------------------------------
#
# Versioned + SSE-S3 + Public Access Block. Versioning is required for
# environments/prod's `use_lockfile = true` native S3 locking to work
# (no DynamoDB lock table in this design -- see design.md).

resource "aws_s3_bucket" "state" {
  bucket = local.state_bucket_name
}

resource "aws_s3_bucket_versioning" "state" {
  bucket = aws_s3_bucket.state.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "state" {
  bucket = aws_s3_bucket.state.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_public_access_block" "state" {
  bucket = aws_s3_bucket.state.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

# --- GitHub OIDC provider ----------------------------------------------------

data "tls_certificate" "github" {
  url = "https://token.actions.githubusercontent.com/.well-known/openid-configuration"
}

resource "aws_iam_openid_connect_provider" "github" {
  url             = "https://token.actions.githubusercontent.com"
  client_id_list  = ["sts.amazonaws.com"]
  thumbprint_list = [data.tls_certificate.github.certificates[0].sha1_fingerprint]
}
