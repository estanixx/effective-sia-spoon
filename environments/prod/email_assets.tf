# Hosts the 120px logo referenced by seat-alert.html's <img> tag. Public-read
# S3, narrowly scoped to assets/* only (design.md "Hosting decision" --
# base64 data-URI is disqualified because Gmail does not render `data:`
# image sources and the recipient list is Gmail/unal.edu.co-heavy;
# CloudFront+OAC is disproportionate for one ~11KB PNG).

resource "aws_s3_bucket" "email_assets" {
  bucket = "${var.name_prefix}-email-assets-${data.aws_caller_identity.current.account_id}"
}

resource "aws_s3_bucket_ownership_controls" "email_assets" {
  bucket = aws_s3_bucket.email_assets.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

# block_public_acls/ignore_public_acls stay true -- no ACL path is ever
# opened. Only block_public_policy/restrict_public_buckets are false, and
# only the bucket policy below (scoped to assets/*) grants any public read.
resource "aws_s3_bucket_public_access_block" "email_assets" {
  bucket = aws_s3_bucket.email_assets.id

  block_public_acls       = true
  block_public_policy     = false
  ignore_public_acls      = true
  restrict_public_buckets = false
}

data "aws_iam_policy_document" "email_assets_public_read" {
  statement {
    sid       = "PublicReadAssetsPrefix"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.email_assets.arn}/assets/*"]

    principals {
      type        = "*"
      identifiers = ["*"]
    }
  }
}

resource "aws_s3_bucket_policy" "email_assets" {
  bucket = aws_s3_bucket.email_assets.id
  policy = data.aws_iam_policy_document.email_assets_public_read.json

  depends_on = [aws_s3_bucket_public_access_block.email_assets]
}

# Committed build output (scripts/build-logo-asset.sh), not built by CI --
# deterministic, reviewable in a PR bytes-and-all.
resource "aws_s3_object" "logo" {
  bucket       = aws_s3_bucket.email_assets.id
  key          = "assets/logo.png"
  source       = "${path.module}/../../email/assets/logo.png"
  etag         = filemd5("${path.module}/../../email/assets/logo.png")
  content_type = "image/png"

  # Immutable: a logo update means a new key/object, not overwriting this
  # one under a long-lived cache header.
  cache_control = "public, max-age=31536000, immutable"
}
