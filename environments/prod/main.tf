# Wires modules/lambda-container-function per its documented contract (see
# modules/lambda-container-function/{variables,outputs}.tf and design.md's
# "Module contract for batch 3" note): policy_statements carries only the
# two caller-specific grants below -- ssm:GetParameter and ses:SendEmail.
# The module always adds its own logs:CreateLogStream/PutLogEvents statement
# internally, scoped to its own log group, to avoid a Terraform dependency
# cycle -- do NOT add a third, logging statement here.

module "watcher" {
  source = "../../modules/lambda-container-function"

  function_name = "course-seat-watcher"
  name_prefix   = var.name_prefix
  image_uri     = "${var.ecr_repository_url}:${var.image_tag}"

  permissions_boundary_arn = var.lambda_exec_boundary_arn

  policy_statements = [
    {
      sid       = "ReadWatcherConfig"
      actions   = ["ssm:GetParameter"]
      resources = [aws_ssm_parameter.watcher_config.arn]
    },
    {
      sid       = "SendSeatAlertEmail"
      actions   = ["ses:SendEmail"]
      resources = [aws_sesv2_email_identity.sender.arn, aws_sesv2_configuration_set.watcher.arn]
      conditions = [
        {
          test     = "StringEquals"
          variable = "ses:FromAddress"
          values   = [var.sender_email]
        },
      ]
    },
  ]
}
