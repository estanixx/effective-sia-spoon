data "aws_caller_identity" "current" {}

# Sender identity: a single verified address, not a domain -- no owned
# domain is confirmed for this project (design.md open question; revisit
# to enable a branded From address + DKIM once one exists).
resource "aws_sesv2_email_identity" "sender" {
  email_identity = var.sender_email
}

# Reputation metrics on so the two monitoring.tf alarms (and any future ones)
# have bounce/complaint data to alarm on, not just delivery counts.
resource "aws_sesv2_configuration_set" "watcher" {
  configuration_set_name = "${var.name_prefix}-watcher"

  reputation_options {
    reputation_metrics_enabled = true
  }
}

# Sandbox-only: while the account has not been granted SES production
# access, both sender AND every recipient must be a verified identity
# (design.md "SES sandbox constraint"). Recipients otherwise live in SSM,
# not Terraform, so this list exists purely to satisfy that sandbox
# requirement -- each owner clicks a verification link once. Emptying
# var.sandbox_verified_recipients is the visible marker that production
# access has landed.
resource "aws_sesv2_email_identity" "sandbox_recipients" {
  for_each = toset(var.sandbox_verified_recipients)

  email_identity = each.value
}
