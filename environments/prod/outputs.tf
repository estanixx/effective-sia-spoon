output "watcher_function_arn" {
  description = "ARN of the deployed course-seat-watcher Lambda."
  value       = module.watcher.function_arn
}

output "watcher_function_name" {
  description = "Deployed function name of course-seat-watcher."
  value       = module.watcher.function_name
}

output "watcher_log_group_name" {
  description = "CloudWatch Logs log group name for course-seat-watcher."
  value       = module.watcher.log_group_name
}

output "ssm_config_parameter_name" {
  description = "Name of the SSM parameter holding the watcher's runtime config, for use with `aws ssm put-parameter --overwrite`."
  value       = aws_ssm_parameter.watcher_config.name
}

output "ops_topic_arn" {
  description = "ARN of the ops-alerts SNS topic, for adding further subscriptions out of band if ever needed."
  value       = aws_sns_topic.ops_alerts.arn
}

output "email_assets_bucket" {
  description = "Name of the public-read S3 bucket serving the email logo asset."
  value       = aws_s3_bucket.email_assets.bucket
}
