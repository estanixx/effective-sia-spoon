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
