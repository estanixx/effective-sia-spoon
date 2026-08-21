output "state_bucket_name" {
  description = "Name of the S3 bucket that holds Terraform state for all root modules. Set as the GitHub repo variable TF_STATE_BUCKET."
  value       = aws_s3_bucket.state.bucket
}

output "plan_role_arn" {
  description = "ARN of the read-only IAM role assumed by pr.yml via OIDC. Set as the GitHub repo variable AWS_PLAN_ROLE_ARN."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "ARN of the scoped-write IAM role assumed by cd.yml via OIDC. Set as the GitHub repo variable AWS_APPLY_ROLE_ARN."
  value       = aws_iam_role.apply.arn
}

output "lambda_exec_boundary_arn" {
  description = "ARN of the permissions boundary policy required (via the apply role's iam:CreateRole condition, see iam.tf) on the Lambda execution role. Pass to environments/prod as var.lambda_exec_boundary_arn."
  value       = aws_iam_policy.lambda_exec_boundary.arn
}

output "ecr_repository_url" {
  description = "URL of the ECR repository hosting the Lambda container image. Set as the GitHub repo variable ECR_REPOSITORY_URL."
  value       = aws_ecr_repository.watcher.repository_url
}
