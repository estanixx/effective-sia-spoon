terraform {
  # Partial backend config. `bucket` is deliberately absent: it is
  # account-derived in bootstrap/main.tf's `state_bucket_name` local and is
  # only known after `bootstrap/` has been applied, so hardcoding it here
  # would create a second source of truth. Supply it at init time:
  #
  #   terraform init -backend-config="bucket=$TF_STATE_BUCKET"
  #
  # or use scripts/tf-init.sh, which wraps this for you.
  #
  # No `dynamodb_table`: locking uses native S3 conditional writes
  # (`use_lockfile`), which requires the state bucket to have versioning
  # enabled (bootstrap/main.tf enables it).
  backend "s3" {
    key          = "environments/prod/terraform.tfstate"
    region       = "us-east-1"
    use_lockfile = true
  }
}
