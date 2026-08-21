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

  # These three are deploy-time infrastructure values Terraform already
  # knows exactly (a verified SES identity, a configuration-set name, a
  # public asset URL) -- not operator-mutable business config, so they
  # belong here rather than in the SSM parameter (design.md's SSM schema
  # deliberately has no fields for them; SSM stays scoped to
  # courses/filters/recipients, the values an operator edits post-deploy).
  environment_variables = {
    SENDER_EMAIL          = var.sender_email
    SES_CONFIGURATION_SET = aws_sesv2_configuration_set.watcher.configuration_set_name
    LOGO_URL              = "https://${aws_s3_bucket.email_assets.bucket}.s3.${var.region}.amazonaws.com/${aws_s3_object.logo.key}"
  }

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
