output "function_arn" {
  description = "ARN of the deployed Lambda function. Used by EventBridge Scheduler targets and by aws_lambda_permission (if ever needed) in environments/prod."
  value       = aws_lambda_function.this.arn
}

output "function_name" {
  description = "Deployed Lambda function name (\"$${name_prefix}-$${function_name}\"), for EventBridge Scheduler target wiring and CloudWatch alarm FunctionName dimensions."
  value       = aws_lambda_function.this.function_name
}

output "log_group_name" {
  description = "Name of the module-created CloudWatch Logs log group."
  value       = aws_cloudwatch_log_group.this.name
}

output "log_group_arn" {
  description = "ARN of the module-created CloudWatch Logs log group."
  value       = aws_cloudwatch_log_group.this.arn
}
