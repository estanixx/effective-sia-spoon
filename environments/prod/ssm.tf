# Non-secret watcher config (courses, filters, recipients) -- Terraform
# seeds the value at first apply so the Lambda can never fail on a missing
# parameter, then `lifecycle { ignore_changes = [value] }` means every
# subsequent `aws ssm put-parameter --overwrite` by an operator survives
# `terraform apply`. `name`/`type`/`tags` stay Terraform-managed, so drift
# there is still detected and corrected (design.md "SSM parameter -- shape
# and lifecycle"). `String`, not `SecureString`: this is non-secret config,
# and a SecureString here would still show up in state anyway.
#
# Consequence accepted per design.md: `terraform plan` refreshes this
# parameter's value, so recipient email addresses land in Terraform state.
# State is private, versioned, SSE-S3-encrypted, and only the two OIDC roles
# (bootstrap/iam.tf) can read it.

resource "aws_ssm_parameter" "watcher_config" {
  name        = "/${var.name_prefix}/prod/watcher/config"
  description = "Course-seat-watcher runtime config (courses, SIA filters, recipients) read once per invocation by lambda/course-seat-watcher/config.py. Value is operator-managed after the initial seed -- see this file's header comment."
  type        = "String"

  value = jsonencode({
    version     = 1
    catalog_url = "https://sia.unal.edu.co/Catalogo/facespublico/public/servicioPublico.jsf?taskflowId=task-flow-AC_CatalogoAsignaturas"
    filters     = {}
    courses     = []
    recipients  = []
  })

  tags = {
    ManagedBy = "terraform"
  }

  lifecycle {
    ignore_changes = [value]
  }
}
