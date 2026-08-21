variable "region" {
  description = "AWS region for environments/prod resources. Must match backend.tf's region."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix applied to environments/prod resource names and default tags, kept consistent with bootstrap's name_prefix."
  type        = string
  default     = "sia"
}

# Comes from bootstrap's `lambda_exec_boundary_arn` output. The apply role's
# iam:CreateRole grant only allows creating a role/sia-* when this exact
# policy is attached as its permissions boundary (bootstrap/iam.tf's
# CreateScopedExecRole statement), so this has no default and must be
# supplied explicitly, e.g.:
#   -var "lambda_exec_boundary_arn=$(terraform -chdir=bootstrap output -raw lambda_exec_boundary_arn)"
variable "lambda_exec_boundary_arn" {
  description = "ARN of the permissions boundary policy from bootstrap's lambda_exec_boundary_arn output. Applied to the Lambda execution role AND the EventBridge Scheduler invoke role in schedule.tf -- the apply role's iam:CreateRole grant conditions on this boundary for every role/sia-* it creates, not only the Lambda's."
  type        = string
}

# Comes from bootstrap's `ecr_repository_url` output.
variable "ecr_repository_url" {
  description = "URL of the ECR repository from bootstrap's ecr_repository_url output. Combined with var.image_tag to build the Lambda's image_uri."
  type        = string
}

variable "image_tag" {
  description = "Tag of the image to deploy, e.g. \"sha-<commit-sha>\". Passed as TF_VAR_image_tag by pr.yml (PR head SHA) and cd.yml (merge SHA) -- see design.md's CI/CD section. No default: every plan/apply must be explicit about which image it deploys."
  type        = string
}

variable "ops_email" {
  description = "Email address subscribed to the sia-ops-alerts SNS topic (monitoring.tf). Must differ from every seat-notification recipient in the SSM config -- ops alarms and seat alerts are deliberately separate channels."
  type        = string
}

variable "sender_email" {
  description = "SES sender identity verified for outbound seat-notification email (ses.tf). A single verified address, not a domain -- no owned domain is confirmed for this project (design.md open question)."
  type        = string
}

variable "sandbox_verified_recipients" {
  description = "Recipient email addresses to verify as individual SES identities while the account is in the SES sandbox, where both sender and every recipient must be a verified identity (design.md 'SES sandbox constraint'). Emptying this list is the visible marker that production access has landed -- recipients otherwise live in SSM, not Terraform."
  type        = list(string)
  default     = []
}

variable "profile" {
  description = "AWS profile to use for environments/prod resources. Empty string (default) means no override -- ambient credentials are used (required in CI, which has no named local profile). Set locally via TF_VAR_profile or -var if your account needs a specific profile."
  type        = string
  default     = ""
}
