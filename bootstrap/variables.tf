variable "github_org" {
  description = "GitHub organization or user that owns the repository. Used to scope the OIDC trust policy `sub` conditions."
  type        = string
  default     = "estanixx"
}

variable "github_repo" {
  description = "GitHub repository name. Used to scope the OIDC trust policy `sub` conditions."
  type        = string
  default     = "effective-sia-spoon"
}

# GitHub's default OIDC `sub` claim prefix embeds these immutable IDs
# (`repo:<org>@<org_id>/<repo>@<repo_id>:...`) instead of the plain
# `repo:<org>/<repo>:...` form older docs describe -- confirmed via
# `gh api repos/{owner}/{repo}/actions/oidc/customization/sub`. IDs never
# change even if the org/repo is renamed; re-derive with:
#   gh api repos/<org>/<repo> --jq '.owner.id, .id'
variable "github_org_id" {
  description = "Immutable GitHub organization/user ID, embedded in the default OIDC `sub` claim prefix."
  type        = string
  default     = "43096620"
}

variable "github_repo_id" {
  description = "Immutable GitHub repository ID, embedded in the default OIDC `sub` claim prefix."
  type        = string
  default     = "1342031765"
}

variable "region" {
  description = "AWS region for the state bucket, IAM resources, and ECR repository."
  type        = string
  default     = "us-east-1"
}

variable "name_prefix" {
  description = "Prefix applied to every bootstrap resource name (state bucket, IAM roles, IAM policies, ECR repository)."
  type        = string
  default     = "sia"
}

variable "profile" {
  description = "AWS profile to use for bootstrap resources. Empty string (default) means no override -- ambient credentials are used (required in CI, which has no named local profile). Set locally via TF_VAR_profile or -var if your account needs a specific profile."
  type        = string
  default     = ""
}
