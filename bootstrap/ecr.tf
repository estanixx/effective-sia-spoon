# --- ECR repository for the Lambda container image -------------------------
#
# Net-new, no precedent in dcuero-iac (dcuero-iac ships zip-packaged Lambdas
# only). Lives in bootstrap/, not environments/prod/, so the registry exists
# before any CD run -- this breaks the image/Lambda chicken-and-egg problem
# structurally: cd.yml can build and push the image before the very first
# `terraform apply` against environments/prod ever runs. Same "one-time
# trust anchor" class as the state bucket above (design.md §1).

resource "aws_ecr_repository" "watcher" {
  name = "${var.name_prefix}/course-seat-watcher"

  # A given commit-SHA tag can never be repointed once pushed -- the
  # deployed image bytes are always provable from the tag alone.
  image_tag_mutability = "IMMUTABLE"

  image_scanning_configuration {
    scan_on_push = true
  }

  encryption_configuration {
    # No CMK in scope -- mirrors the state bucket's SSE-S3 choice and the
    # same .checkov.yml CKV_AWS_145 reasoning dcuero-iac already applies.
    encryption_type = "AES256"
  }
}

# Untagged images (superseded digests from a repointed `latest`-style flow,
# which this design never uses, but a manual push could still leave one
# behind) are pruned after 1 day. Tagged (`sha-*`) images are pruned beyond
# the last 10 -- unbounded retention is the real cost risk at ~1.4GB/image;
# 10 keeps a usable rollback depth (design.md §1).
# Real, live failure: Lambda's CreateFunction rejected the image with
# "AccessDeniedException: Lambda does not have permission to access the
# ECR image" -- distinct failure class from every other IAM gap this
# session. Those were all about the *apply role's* identity-based IAM
# policy (what sia-apply is allowed to do); this is about the AWS Lambda
# *service* itself needing a resource-based policy directly on the ECR
# repository to pull image layers at function-create/cold-start time --
# no assumed role is involved in that pull, so no identity policy can
# grant it. `aws:SourceAccount` (not `aws:SourceArn`) is the condition
# here deliberately: this repository's policy lives in bootstrap/, a
# separate Terraform root from environments/prod where the Lambda
# function itself is defined, so the function's ARN isn't known here to
# pin against -- scoping to "any Lambda in this account" is the
# pragmatic equivalent AWS's own documented cross-service examples use
# when the exact caller ARN isn't available.
data "aws_iam_policy_document" "ecr_lambda_access" {
  statement {
    sid    = "LambdaECRImageRetrievalPolicy"
    effect = "Allow"

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }

    actions = [
      "ecr:BatchGetImage",
      "ecr:GetDownloadUrlForLayer",
    ]

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

resource "aws_ecr_repository_policy" "watcher" {
  repository = aws_ecr_repository.watcher.name
  policy     = data.aws_iam_policy_document.ecr_lambda_access.json
}

resource "aws_ecr_lifecycle_policy" "watcher" {
  repository = aws_ecr_repository.watcher.name

  policy = jsonencode({
    rules = [
      {
        rulePriority = 1
        description  = "Expire untagged images after 1 day"
        selection = {
          tagStatus   = "untagged"
          countType   = "sinceImagePushed"
          countUnit   = "days"
          countNumber = 1
        }
        action = {
          type = "expire"
        }
      },
      {
        rulePriority = 2
        description  = "Keep only the last 10 sha-tagged images"
        selection = {
          tagStatus     = "tagged"
          tagPrefixList = ["sha-"]
          countType     = "imageCountMoreThan"
          countNumber   = 10
        }
        action = {
          type = "expire"
        }
      }
    ]
  })
}
