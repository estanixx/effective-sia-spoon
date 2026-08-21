variable "function_name" {
  description = "Bare function name, e.g. \"course-seat-watcher\". The deployed Lambda function name and its execution role name are both derived as \"$${name_prefix}-$${function_name}\" (see main.tf) so bootstrap's apply-role grant, scoped to role/$${name_prefix}-*, actually matches."
  type        = string
}

variable "image_uri" {
  description = "Full ECR image URI including tag, e.g. \"<account>.dkr.ecr.<region>.amazonaws.com/sia/course-seat-watcher:sha-<sha>\". This module has no zip/discovery path (design.md 'Fresh modules/lambda-container-function, not a fork' decision) -- package_type is always \"Image\"."
  type        = string
}

variable "name_prefix" {
  description = "Prefix applied to the Lambda function name and its execution role name, kept consistent with bootstrap's and environments/prod's name_prefix."
  type        = string
  default     = "sia"
}

variable "memory_size" {
  description = "Lambda memory (MB). Also scales allotted vCPU (~1.2 vCPU at 2048MB). Default sized for headless Firefox's ~1GB RSS plus scrape-latency-dominated cost (design.md 'Sizing')."
  type        = number
  default     = 2048
}

variable "timeout" {
  description = "Lambda timeout (seconds). Must stay strictly below the invocation schedule's interval (600s) so overlapping invocations are structurally impossible -- do not raise this to 900s (design.md 'Sizing')."
  type        = number
  default     = 300
}

variable "ephemeral_storage_size" {
  description = "Lambda /tmp size (MB). Default 512MB is tight for a Firefox profile + cache under /tmp (the container filesystem is otherwise read-only)."
  type        = number
  default     = 1024
}

variable "architecture" {
  description = "Lambda instruction set architecture. Default is x86_64, a deliberate deviation from this repo family's usual arm64 default: Mozilla does not publish official aarch64 Linux Firefox/geckodriver builds on the same footing as x86_64 (design.md 'Sizing'). Do not change to arm64 without re-verifying that constraint."
  type        = string
  default     = "x86_64"

  validation {
    condition     = contains(["x86_64", "arm64"], var.architecture)
    error_message = "architecture must be \"x86_64\" or \"arm64\"."
  }
}

variable "reserved_concurrent_executions" {
  description = "Reserved concurrency ceiling. Default 1 is a hard guarantee against a second invocation overlapping the first and double-sending a notification email (design.md 'Sizing')."
  type        = number
  default     = 1
}

variable "environment_variables" {
  description = "Map of environment variable name => value passed to the function. Empty by default -- this design's handler reads its config from SSM at invocation time (config.py), not from Lambda environment variables, so callers typically leave this empty or use it only for non-secret, non-config toggles."
  type        = map(string)
  default     = {}
}

variable "policy_statements" {
  description = "Additional inline IAM policy statements granted to the function's execution role, beyond the CloudWatch Logs statement this module always adds for its own log group (see main.tf -- the log group is created here specifically so that statement can be scoped to a known ARN instead of \"*\"). Each entry models one design.md 'Lambda exec role' grant, e.g. ssm:GetParameter on one parameter ARN, or ses:SendEmail with a StringEquals ses:FromAddress condition."
  type = list(object({
    sid       = string
    effect    = optional(string, "Allow")
    actions   = list(string)
    resources = list(string)
    conditions = optional(list(object({
      test     = string
      variable = string
      values   = list(string)
    })), [])
  }))
  default = []
}

variable "permissions_boundary_arn" {
  description = "ARN of the IAM permissions boundary policy applied to the execution role. Defaults to null so the module works standalone without one; environments/prod passes bootstrap's lambda_exec_boundary_arn output here -- required in practice, since the apply role's iam:CreateRole grant is conditioned on a boundary being attached (bootstrap/iam.tf)."
  type        = string
  default     = null
}

variable "log_retention_days" {
  description = "CloudWatch Logs retention (days) for the function's log group. Mirrors dcuero-iac's default."
  type        = number
  default     = 14
}
