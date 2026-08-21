# Reusable module wrapping a single container-image Lambda function. Written
# fresh rather than forked from dcuero-iac's modules/lambda-function (design.md
# "Fresh modules/lambda-container-function, not a fork" decision): that module's
# entire value is (a) fileset()-based multi-function discovery and (b)
# delegating packaging to terraform-aws-modules/lambda/aws, which only builds
# zip artifacts. For a container image, packaging happens in Docker (CI/CD),
# so (b) is void; this repo has exactly one function, so (a) is void -- and its
# discovery globs would find lambda/course-seat-watcher/handler.py and zip-
# package it, silently producing the wrong deployment artifact. There is no
# discovery-by-filename anywhere in this module: image_uri is always an
# explicit input.

locals {
  full_name = "${var.name_prefix}-${var.function_name}"
}

# Created here (rather than left to the caller) so its ARN is known at plan
# time and the module's own CloudWatch Logs grant (below) can be scoped to it
# instead of "*". Scoping the role's log-write grant to a caller-supplied ARN
# would require the caller to reference this module's own output back into an
# input, an unresolvable cycle -- so the module creates the log group AND its
# own logging statement internally.
resource "aws_cloudwatch_log_group" "this" {
  name              = "/aws/lambda/${local.full_name}"
  retention_in_days = var.log_retention_days
}

data "aws_iam_policy_document" "assume_role" {
  statement {
    sid     = "AllowLambdaAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["lambda.amazonaws.com"]
    }
  }
}

resource "aws_iam_role" "this" {
  name                 = local.full_name
  assume_role_policy   = data.aws_iam_policy_document.assume_role.json
  permissions_boundary = var.permissions_boundary_arn
}

data "aws_iam_policy_document" "this" {
  # Always present: the module-owned log group above. ":*" scopes to log
  # streams within the group (AWS's own documented pattern for
  # logs:CreateLogStream/PutLogEvents), narrower than granting the bare
  # log-group ARN.
  statement {
    sid       = "AllowLogging"
    effect    = "Allow"
    actions   = ["logs:CreateLogStream", "logs:PutLogEvents"]
    resources = ["${aws_cloudwatch_log_group.this.arn}:*"]
  }

  dynamic "statement" {
    for_each = var.policy_statements
    content {
      sid       = statement.value.sid
      effect    = statement.value.effect
      actions   = statement.value.actions
      resources = statement.value.resources

      dynamic "condition" {
        for_each = statement.value.conditions
        content {
          test     = condition.value.test
          variable = condition.value.variable
          values   = condition.value.values
        }
      }
    }
  }
}

# Inline (not a managed-policy attachment) per design.md's module surface --
# keeps the role's full grant set in one place, reviewable alongside the role
# itself instead of split across a separate policy resource with its own
# lifecycle.
resource "aws_iam_role_policy" "this" {
  name   = local.full_name
  role   = aws_iam_role.this.id
  policy = data.aws_iam_policy_document.this.json
}

resource "aws_lambda_function" "this" {
  function_name = local.full_name
  role          = aws_iam_role.this.arn

  # Always Image: Firefox cannot ship in a zip package (design.md "Sizing").
  package_type = "Image"
  image_uri    = var.image_uri

  memory_size                    = var.memory_size
  timeout                        = var.timeout
  architectures                  = [var.architecture]
  reserved_concurrent_executions = var.reserved_concurrent_executions

  ephemeral_storage {
    size = var.ephemeral_storage_size
  }

  environment {
    variables = var.environment_variables
  }

  # Explicit dependency: the role's inline policy must exist before Lambda
  # can assume/exercise the role, and the log group must exist before the
  # first invocation writes to it. Terraform would infer the role edge from
  # `role = aws_iam_role.this.arn` alone, but the *policy* and *log group*
  # are otherwise only reachable indirectly (through the role and through
  # the policy document data source) -- spelling them out here avoids a
  # first-invocation race between "role assumed" and "inline policy
  # attached"/"log group exists".
  depends_on = [
    aws_iam_role_policy.this,
    aws_cloudwatch_log_group.this,
  ]
}
