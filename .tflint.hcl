# The `terraform` ruleset (deprecated-syntax, unused declarations, naming
# conventions, etc.) is bundled directly into the tflint CLI core since
# v0.42 and its recommended rules are enabled by default -- there is no
# `plugin "terraform"` block to declare, only `rule` overrides if ever
# needed. See https://github.com/terraform-linters/tflint-ruleset-terraform.

plugin "aws" {
  enabled = true
  version = "0.48.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}

config {
  # Local modules (modules/lambda-container-function) are inspected in
  # place, not skipped.
  call_module_type = "local"
}
