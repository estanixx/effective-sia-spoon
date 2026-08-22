# Two OIDC roles, per design.md §5:
#   - plan role:  read-only, trusted for GitHub's `pull_request` event
#   - apply role: scoped write, trusted only for pushes to refs/heads/main
#
# Both trust policies use StringEquals (never StringLike) on both `aud` and
# `sub` -- no wildcards, so a fork, a tag, or `refs/heads/main-x` cannot
# assume either role.

# --- Plan role: trust ---------------------------------------------------

data "aws_iam_policy_document" "plan_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}@${var.github_org_id}/${var.github_repo}@${var.github_repo_id}:pull_request"]
    }
  }
}

# --- Plan role: permissions (read/plan only) -----------------------------
#
# `terraform plan` never persists state, so s3:PutObject on the state
# object itself is deliberately absent -- the only write grant is the
# `.tflock` object. This same policy is reused as the role's *identity*
# policy (attached below) and as its *permissions boundary*, so even a
# future mis-attached AdministratorAccess policy cannot make the plan role
# mutating.
#
# No ECR grant at all here (design.md §1) -- image_uri is a plain string
# built from the repo URL + var.image_tag, so `terraform plan` never calls
# ECR; only the apply role (cd.yml) pushes images.

data "aws_iam_policy_document" "plan_permissions" {
  statement {
    sid    = "ReadAwsSurface"
    effect = "Allow"
    actions = [
      "lambda:Get*",
      "lambda:List*",
      "iam:Get*",
      "iam:List*",
      "logs:Describe*",
      "logs:ListTagsForResource",
      "ssm:DescribeParameters",
      "ssm:GetParameter*",
      "ssm:ListTagsForResource",
      "scheduler:Get*",
      "scheduler:List*",
      "ses:Get*",
      "ses:List*",
      "ses:Describe*",
      "sesv2:Get*",
      "sesv2:List*",
      "sns:Get*",
      "sns:List*",
      "cloudwatch:Describe*",
      "cloudwatch:List*",
      "cloudwatch:Get*",
      "kms:DescribeKey",
      "sts:GetCallerIdentity",
    ]
    resources = ["*"]
  }

  statement {
    sid       = "ReadState"
    effect    = "Allow"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.state.arn}/environments/prod/terraform.tfstate"]
  }

  statement {
    sid    = "TakeStateLock"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.state.arn}/environments/prod/terraform.tfstate.tflock"]
  }

  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["environments/prod/*"]
    }
  }

  statement {
    # Read-only mirror of the apply role's S3BucketManagement statement
    # below, scoped to the same sia-* bucket-naming convention, so
    # `terraform plan` can diff the email-assets bucket without needing
    # write access.
    #
    # s3:ListBucket must stay unconditional here too -- see the
    # S3BucketManagement comment below for why (HeadBucket carries no
    # s3:prefix, so a ListStateBucket-style condition never matches).
    #
    # The last six actions below (GetBucketWebsite through
    # GetBucketNotification) exist because aws_s3_bucket's refresh reads
    # more sub-resources than create/import does -- confirmed live: a real
    # `terraform plan` failed with AccessDenied on s3:GetBucketWebsite
    # alone, on a bucket that had *just* imported cleanly, because import
    # only wrote the initial state and the very next refresh already
    # needed a permission nothing above granted. Same failure-shape as the
    # s3:ListBucket gap: silently narrower actual requirements than what
    # "the bucket CRUD actions" looks like it should cover.
    sid    = "ReadS3BucketConfig"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:GetBucketTagging",
      "s3:GetBucketVersioning",
      "s3:GetBucketPublicAccessBlock",
      "s3:GetBucketPolicy",
      "s3:GetBucketOwnershipControls",
      "s3:GetEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:GetBucketAcl",
      "s3:GetBucketLogging",
      "s3:GetBucketCORS",
      "s3:GetBucketWebsite",
      "s3:GetAccelerateConfiguration",
      "s3:GetBucketRequestPayment",
      "s3:GetBucketObjectLockConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:GetBucketNotification",
    ]
    resources = ["arn:aws:s3:::sia-*"]
  }

  statement {
    # Read-only mirror of the apply role's EmailAssetsObjectCrud statement
    # below -- missed when that statement was first added (PR12) because
    # nothing at the time confirmed the plan role also refreshes
    # aws_s3_object.logo. Confirmed live: a real `terraform plan` failed
    # with AccessDenied on s3:GetObjectTagging for this exact object,
    # since object-level access was never granted to sia-plan at all (only
    # bucket-level config, via ReadS3BucketConfig above). GetObject is
    # included alongside GetObjectTagging since the object's own
    # refresh/diff needs both, not just the tagging call that happened to
    # surface first.
    sid    = "ReadEmailAssetsObject"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:GetObjectTagging",
    ]
    resources = ["arn:aws:s3:::${var.name_prefix}-email-assets-${data.aws_caller_identity.current.account_id}/*"]
  }
}

resource "aws_iam_policy" "plan_permissions" {
  name        = "${var.name_prefix}-plan-permissions"
  description = "Read-only permissions for the Terraform plan role; also attached as its permissions boundary."
  policy      = data.aws_iam_policy_document.plan_permissions.json
}

resource "aws_iam_role" "plan" {
  name                 = local.plan_role_name
  description          = "Assumed by pr.yml via OIDC to run `terraform plan` against environments/prod."
  assume_role_policy   = data.aws_iam_policy_document.plan_trust.json
  permissions_boundary = aws_iam_policy.plan_permissions.arn
}

resource "aws_iam_role_policy_attachment" "plan" {
  role       = aws_iam_role.plan.name
  policy_arn = aws_iam_policy.plan_permissions.arn
}

# --- Apply role: trust ----------------------------------------------------

data "aws_iam_policy_document" "apply_trust" {
  statement {
    effect  = "Allow"
    actions = ["sts:AssumeRoleWithWebIdentity"]

    principals {
      type        = "Federated"
      identifiers = [data.aws_iam_openid_connect_provider.github.arn]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:aud"
      values   = ["sts.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "token.actions.githubusercontent.com:sub"
      values   = ["repo:${var.github_org}@${var.github_org_id}/${var.github_repo}@${var.github_repo_id}:ref:refs/heads/main"]
    }
  }
}

# --- Exec-role boundary --------------------------------------------------
#
# Attached (via the CreateRole condition below) to the Lambda execution role
# the apply role creates in environments/prod. Baseline allow, with an
# explicit deny on IAM/organization/account management so the created exec
# role can never escalate regardless of the identity policy
# modules/lambda-container-function attaches to it. The exact allow-list of
# exec-role actions (log group, ssm:GetParameter, ses:SendEmail) is scoped
# by that module; this boundary is the outer cap, not the inner grant.

data "aws_iam_policy_document" "lambda_exec_boundary" {
  statement {
    sid       = "AllowWithinBoundary"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  statement {
    sid       = "DenyIamEscalation"
    effect    = "Deny"
    actions   = ["iam:*"]
    resources = ["*"]
  }

  statement {
    sid    = "DenyAccountAndOrgManagement"
    effect = "Deny"
    actions = [
      "organizations:*",
      "account:*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "lambda_exec_boundary" {
  name        = "${var.name_prefix}-lambda-exec-boundary"
  description = "Permissions boundary required on the Lambda exec role created by the apply role."
  policy      = data.aws_iam_policy_document.lambda_exec_boundary.json
}

# --- Apply role: permissions (scoped write) -------------------------------

data "aws_iam_policy_document" "apply_permissions" {
  statement {
    sid    = "LambdaLogsFullAccess"
    effect = "Allow"
    actions = [
      "lambda:*",
      "logs:*",
    ]
    # ARNs are unknown pre-creation (the function name comes from
    # modules/lambda-container-function, added by a later PR); capped by
    # the apply-role permissions boundary below.
    resources = ["*"]
  }

  statement {
    sid       = "SsmParameterAccess"
    effect    = "Allow"
    actions   = ["ssm:*"]
    resources = ["arn:aws:ssm:${var.region}:${data.aws_caller_identity.current.account_id}:parameter/sia/prod/*"]
  }

  statement {
    # DescribeParameters (called by the aws_ssm_parameter resource during
    # plan/apply/refresh) does not support resource-level permissions at
    # all -- AWS always evaluates it against "*", so scoping it to
    # parameter/sia/prod/* above silently denies it. Mirrors the plan
    # role's "ReadAwsSurface" statement, which already grants this the
    # same way.
    sid       = "SsmDescribeParameters"
    effect    = "Allow"
    actions   = ["ssm:DescribeParameters"]
    resources = ["*"]
  }

  statement {
    sid    = "StateObjectCrud"
    effect = "Allow"
    actions = [
      "s3:GetObject",
      "s3:PutObject",
      "s3:DeleteObject",
    ]
    resources = ["${aws_s3_bucket.state.arn}/environments/prod/*"]
  }

  statement {
    sid       = "ListStateBucket"
    effect    = "Allow"
    actions   = ["s3:ListBucket"]
    resources = [aws_s3_bucket.state.arn]

    condition {
      test     = "StringLike"
      variable = "s3:prefix"
      values   = ["environments/prod/*"]
    }
  }

  statement {
    sid       = "CreateScopedExecRole"
    effect    = "Allow"
    actions   = ["iam:CreateRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/sia-*"]

    # `iam:PermissionsBoundary` is only present in the request context for
    # boundary-setting calls (CreateRole / PutRolePermissionsBoundary); it
    # is intentionally scoped to this statement only, not to the broader
    # role-management statement below.
    condition {
      test     = "StringEquals"
      variable = "iam:PermissionsBoundary"
      values   = [aws_iam_policy.lambda_exec_boundary.arn]
    }
  }

  statement {
    sid    = "ManageScopedExecRole"
    effect = "Allow"
    actions = [
      "iam:DeleteRole",
      "iam:GetRole",
      "iam:TagRole",
      "iam:UntagRole",
      "iam:UpdateRole",
      "iam:UpdateAssumeRolePolicy",
      "iam:PutRolePolicy",
      "iam:DeleteRolePolicy",
      "iam:GetRolePolicy",
      "iam:AttachRolePolicy",
      "iam:DetachRolePolicy",
      "iam:ListRolePolicies",
      "iam:ListAttachedRolePolicies",
    ]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/sia-*"]
  }

  statement {
    sid       = "PassExecRole"
    effect    = "Allow"
    actions   = ["iam:PassRole"]
    resources = ["arn:aws:iam::${data.aws_caller_identity.current.account_id}:role/sia-*"]

    condition {
      test     = "StringEquals"
      variable = "iam:PassedToService"
      # lambda.amazonaws.com: the exec role passed to the Lambda function
      # itself. scheduler.amazonaws.com: environments/prod/schedule.tf's
      # shared EventBridge Scheduler invoke role, passed so Scheduler can
      # assume it and call lambda:InvokeFunction.
      values = ["lambda.amazonaws.com", "scheduler.amazonaws.com"]
    }
  }

  statement {
    # Bucket-level create/configure only (no s3:PutObject/GetObject --
    # object CRUD on the email-assets bucket is a separate, narrower grant
    # below). Scoped to the same sia-* naming convention as the IAM role
    # grants above so this can never touch the state bucket's own name;
    # the state bucket's mutating config calls are also explicitly denied
    # by DenyStateBucketConfigMutation in the apply boundary below
    # regardless.
    #
    # s3:ListBucket must be granted here unconditionally for any S3 bucket
    # resource in this account. terraform-provider-aws's aws_s3_bucket
    # create/import path polls HeadBucket to confirm the bucket is ready;
    # HeadBucket is authorized as s3:ListBucket, and it carries no
    # s3:prefix in its request context. Without this grant, AWS returns a
    # bodyless 403 that the provider's waiter cannot tell apart from "not
    # ready yet," so it retries silently until its own internal timeout
    # (~10-20 min) instead of failing fast with a visible AccessDenied.
    # This was the root cause of three real hung `terraform apply` runs
    # against environments/prod's aws_s3_bucket.email_assets this project.
    # Do NOT copy the ListStateBucket pattern above (s3:prefix StringLike
    # condition) onto this grant -- HeadBucket sends no prefix, so a
    # conditioned copy looks complete but silently never matches. If you
    # add the next S3 bucket resource in this repo, this statement's
    # sia-* scope already covers it; keep s3:ListBucket unconditional.
    #
    # Second incident, same shape: fixing the ListBucket gap above got the
    # bucket successfully imported, and the very next `terraform plan`
    # failed with AccessDenied on s3:GetBucketWebsite -- aws_s3_bucket's
    # refresh reads several more sub-resources than create/import touches
    # (website, transfer-acceleration, request-payment, object-lock,
    # replication, notification config), none of which "the bucket CRUD
    # actions" obviously implies. All six read actions are granted below
    # even though this bucket doesn't use most of them, specifically so
    # refresh doesn't fail piecemeal on whichever one gets hit first.
    sid    = "S3BucketManagement"
    effect = "Allow"
    actions = [
      "s3:ListBucket",
      "s3:CreateBucket",
      "s3:DeleteBucket",
      "s3:GetBucketTagging",
      "s3:PutBucketTagging",
      "s3:GetBucketVersioning",
      "s3:PutBucketVersioning",
      "s3:GetBucketPublicAccessBlock",
      "s3:PutBucketPublicAccessBlock",
      "s3:GetBucketPolicy",
      "s3:PutBucketPolicy",
      "s3:DeleteBucketPolicy",
      "s3:GetBucketOwnershipControls",
      "s3:PutBucketOwnershipControls",
      "s3:GetEncryptionConfiguration",
      "s3:PutEncryptionConfiguration",
      "s3:GetLifecycleConfiguration",
      "s3:PutLifecycleConfiguration",
      "s3:GetBucketAcl",
      "s3:PutBucketAcl",
      "s3:GetBucketLogging",
      "s3:PutBucketLogging",
      "s3:GetBucketCORS",
      "s3:PutBucketCORS",
      "s3:GetBucketWebsite",
      "s3:GetAccelerateConfiguration",
      "s3:GetBucketRequestPayment",
      "s3:GetBucketObjectLockConfiguration",
      "s3:GetReplicationConfiguration",
      "s3:GetBucketNotification",
    ]
    resources = ["arn:aws:s3:::sia-*"]
  }

  statement {
    # Object CRUD for the email-assets bucket only (design.md §1,
    # "email_assets.tf") -- the logo PNG object. No other bucket needs
    # object-level access from Terraform.
    #
    # *ObjectTagging is required alongside Put/Get/DeleteObject because the
    # provider's default_tags apply to aws_s3_object too -- confirmed live:
    # PutObjectTagging was denied on the object's first real create, same
    # "CRUD looked complete but wasn't" shape as the bucket-level gaps
    # above. GetObjectTagging is included pre-emptively for the same
    # refresh-needs-more-than-create reason those gaps taught.
    sid    = "EmailAssetsObjectCrud"
    effect = "Allow"
    actions = [
      "s3:PutObject",
      "s3:GetObject",
      "s3:DeleteObject",
      "s3:PutObjectTagging",
      "s3:GetObjectTagging",
    ]
    resources = ["arn:aws:s3:::${var.name_prefix}-email-assets-${data.aws_caller_identity.current.account_id}/*"]
  }

  statement {
    # Both resource types are needed: schedule-group/sia-* for
    # aws_scheduler_schedule_group (CreateScheduleGroup etc. -- a distinct
    # resource type from a schedule itself, confirmed missing here by a
    # live AccessDeniedException on first real apply) and schedule/sia-*
    # for the two aws_scheduler_schedule instances inside that group.
    sid     = "SchedulerManagement"
    effect  = "Allow"
    actions = ["scheduler:*"]
    resources = [
      "arn:aws:scheduler:${var.region}:${data.aws_caller_identity.current.account_id}:schedule-group/sia-*",
      "arn:aws:scheduler:${var.region}:${data.aws_caller_identity.current.account_id}:schedule/sia-*",
    ]
  }

  statement {
    sid    = "SesManagement"
    effect = "Allow"
    actions = [
      "ses:*",
      "sesv2:*",
    ]
    # Sender identity and any sandbox-verified recipient identities (name
    # unknown pre-creation -- domain vs. address is still an open design
    # question, see design.md §6) plus the configuration set. Scoped to
    # this account/region; identity names cannot collide with another
    # project's resources since they are account-scoped ARNs already
    # capped by the apply-role permissions boundary below.
    resources = [
      "arn:aws:ses:${var.region}:${data.aws_caller_identity.current.account_id}:identity/*",
      "arn:aws:ses:${var.region}:${data.aws_caller_identity.current.account_id}:configuration-set/${var.name_prefix}-*",
    ]
  }

  statement {
    sid       = "SnsOpsTopicManagement"
    effect    = "Allow"
    actions   = ["sns:*"]
    resources = ["arn:aws:sns:${var.region}:${data.aws_caller_identity.current.account_id}:sia-*"]
  }

  statement {
    # ListTagsForResource/TagResource/UntagResource are required alongside
    # the alarm-management actions themselves: providers.tf's default_tags
    # block means Terraform reads back and reconciles tags on every
    # resource, including alarms -- confirmed missing here by a live
    # AccessDenied on ListTagsForResource on first real apply.
    sid    = "CloudwatchAlarmManagement"
    effect = "Allow"
    actions = [
      "cloudwatch:PutMetricAlarm",
      "cloudwatch:DeleteAlarms",
      "cloudwatch:DescribeAlarms",
      "cloudwatch:ListTagsForResource",
      "cloudwatch:TagResource",
      "cloudwatch:UntagResource",
    ]
    resources = ["arn:aws:cloudwatch:${var.region}:${data.aws_caller_identity.current.account_id}:alarm:sia-*"]
  }

  statement {
    # GetAuthorizationToken does not support resource-level permissions at
    # all -- AWS always evaluates it against "*" (same class of gap as
    # SsmDescribeParameters above). Justified .checkov.yml skip to follow
    # in the CI/CD work unit (design.md §1).
    sid       = "EcrAuth"
    effect    = "Allow"
    actions   = ["ecr:GetAuthorizationToken"]
    resources = ["*"]
  }

  statement {
    # Push/pull actions scoped to the exact repository ARN -- cd.yml is
    # the only pusher; the plan role gets no ECR grant at all.
    sid    = "EcrPushPull"
    effect = "Allow"
    actions = [
      "ecr:BatchCheckLayerAvailability",
      "ecr:InitiateLayerUpload",
      "ecr:UploadLayerPart",
      "ecr:CompleteLayerUpload",
      "ecr:PutImage",
      "ecr:BatchGetImage",
      "ecr:DescribeImages",
      "ecr:ListImages",
    ]
    resources = [aws_ecr_repository.watcher.arn]
  }
}

resource "aws_iam_role_policy" "apply" {
  name   = "${var.name_prefix}-apply-permissions"
  role   = aws_iam_role.apply.id
  policy = data.aws_iam_policy_document.apply_permissions.json
}

# --- Apply role: permissions boundary -------------------------------------
#
# References the plan/apply role ARNs and the OIDC provider ARN as
# *computed* values (locals, not resource attributes) to avoid a circular
# dependency: the apply role needs this boundary's ARN to be created, so
# this boundary cannot depend on the apply role resource itself.

data "aws_iam_policy_document" "apply_boundary" {
  statement {
    sid       = "AllowWithinBoundary"
    effect    = "Allow"
    actions   = ["*"]
    resources = ["*"]
  }

  statement {
    # `not_actions` (not `actions`) -- denies every IAM action on these
    # three trust-anchor resources EXCEPT reads (Get*/List*). A blanket
    # `iam:*` deny here would also block the apply role's own IAM grants
    # above (an explicit Deny always wins over an Allow, boundary or not).
    # Every mutating action (Update*, Delete*, Tag*,
    # AddClientIDToOpenIDConnectProvider, etc.) is still denied.
    sid    = "DenyTrustAnchorMutation"
    effect = "Deny"
    not_actions = [
      "iam:Get*",
      "iam:List*",
    ]
    resources = [
      local.plan_role_arn,
      local.apply_role_arn,
      data.aws_iam_openid_connect_provider.github.arn,
    ]
  }

  statement {
    sid    = "DenyStateBucketConfigMutation"
    effect = "Deny"
    actions = [
      "s3:DeleteBucket",
      "s3:PutBucketPolicy",
      "s3:PutBucketVersioning",
      "s3:PutBucketPublicAccessBlock",
    ]
    resources = [aws_s3_bucket.state.arn]
  }

  statement {
    sid    = "DenyIamUserCreation"
    effect = "Deny"
    actions = [
      "iam:CreateUser",
      "iam:CreateAccessKey",
      "iam:CreateLoginProfile",
    ]
    resources = ["*"]
  }

  statement {
    sid    = "DenyAccountAndOrgManagement"
    effect = "Deny"
    actions = [
      "organizations:*",
      "account:*",
    ]
    resources = ["*"]
  }
}

resource "aws_iam_policy" "apply_boundary" {
  name        = "${var.name_prefix}-apply-boundary"
  description = "Caps the apply role: cannot widen its own OIDC trust anchor, cannot break state-bucket protections, cannot create IAM users/access keys, no org/account management."
  policy      = data.aws_iam_policy_document.apply_boundary.json
}

resource "aws_iam_role" "apply" {
  name                 = local.apply_role_name
  description          = "Assumed by cd.yml via OIDC to run `terraform apply` against environments/prod and to push the Lambda container image to ECR."
  assume_role_policy   = data.aws_iam_policy_document.apply_trust.json
  permissions_boundary = aws_iam_policy.apply_boundary.arn
}
