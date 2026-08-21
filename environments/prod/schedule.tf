# Bogota is UTC-5 year-round (no DST). Requirement: every 10 minutes,
# 06:00-13:00 local, inclusive of the 13:00 run. That is NOT expressible as
# one cron expression -- minute and hour fields are independent, so "every
# ten-minute mark in hours 6-12 PLUS minute 0 of hour 13" has no single
# cross-product. Two aws_scheduler_schedule instances via for_each, each in
# Bogota local time via schedule_expression_timezone, avoid hand-computed
# UTC entirely (design.md "Schedule").
#
# EventBridge Scheduler (not a classic aws_cloudwatch_event_rule) also means
# both schedules share one IAM invoke role below instead of needing a
# separate aws_lambda_permission per rule.

# Custom group so the group's ARN segment starts with "sia-" -- the apply
# role's SchedulerManagement grant (bootstrap/iam.tf) is scoped to
# schedule/sia-*, and an EventBridge Scheduler ARN is
# schedule/<group-name>/<schedule-name>, so the group name itself must carry
# the prefix for the wildcard to match.
resource "aws_scheduler_schedule_group" "watcher" {
  name = "${var.name_prefix}-watcher"
}

data "aws_iam_policy_document" "scheduler_assume_role" {
  statement {
    sid     = "AllowSchedulerAssumeRole"
    effect  = "Allow"
    actions = ["sts:AssumeRole"]

    principals {
      type        = "Service"
      identifiers = ["scheduler.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "aws:SourceAccount"
      values   = [data.aws_caller_identity.current.account_id]
    }
  }
}

# Name starts with "sia-" (role/sia-* -- required by the apply role's
# CreateScopedExecRole/ManageScopedExecRole/PassExecRole grants), and per
# those same grants must carry the lambda_exec_boundary_arn permissions
# boundary even though this role invokes rather than executes -- the
# CreateRole condition applies to every role/sia-* the apply role creates,
# not only the Lambda's own exec role.
resource "aws_iam_role" "scheduler_invoke" {
  name                 = "${var.name_prefix}-scheduler-invoke"
  description          = "Assumed by EventBridge Scheduler to invoke the course-seat-watcher Lambda on each schedule fire."
  assume_role_policy   = data.aws_iam_policy_document.scheduler_assume_role.json
  permissions_boundary = var.lambda_exec_boundary_arn
}

data "aws_iam_policy_document" "scheduler_invoke" {
  statement {
    sid       = "InvokeWatcher"
    effect    = "Allow"
    actions   = ["lambda:InvokeFunction"]
    resources = [module.watcher.function_arn]
  }
}

resource "aws_iam_role_policy" "scheduler_invoke" {
  name   = "${var.name_prefix}-scheduler-invoke"
  role   = aws_iam_role.scheduler_invoke.id
  policy = data.aws_iam_policy_document.scheduler_invoke.json
}

resource "aws_scheduler_schedule" "watcher" {
  for_each = {
    window   = "cron(0/10 6-12 ? * * *)" # 06:00 .. 12:50 Bogota (42 runs/day)
    boundary = "cron(0 13 ? * * *)"      # 13:00 Bogota exactly (1 run/day)
  }

  name       = "${var.name_prefix}-watcher-${each.key}"
  group_name = aws_scheduler_schedule_group.watcher.name

  schedule_expression          = each.value
  schedule_expression_timezone = "America/Bogota"

  flexible_time_window {
    mode = "OFF"
  }

  target {
    arn      = module.watcher.function_arn
    role_arn = aws_iam_role.scheduler_invoke.arn

    # Retrying a browser scrape is pointless when the next run is 10 minutes
    # away, and a retry risks a duplicate email (design.md).
    retry_policy {
      maximum_retry_attempts = 0
    }
  }
}
