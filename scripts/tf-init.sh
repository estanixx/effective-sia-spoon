#!/usr/bin/env bash
# Wraps `terraform init` for environments/prod's partial S3 backend. The
# state bucket name is account-derived (bootstrap/main.tf's
# `state_bucket_name` local) and only known after `bootstrap/` has been
# applied, so it is injected here from TF_STATE_BUCKET rather than
# hardcoded (design.md "partial backend config" decision).
#
# Usage:
#   export TF_STATE_BUCKET="$(terraform -chdir=bootstrap output -raw state_bucket_name)"
#   ./scripts/tf-init.sh
set -euo pipefail

if [ -z "${TF_STATE_BUCKET:-}" ]; then
  echo "error: TF_STATE_BUCKET is not set." >&2
  echo "Export it to the bucket name from bootstrap's 'state_bucket_name' output, then re-run." >&2
  exit 1
fi

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
target_dir="${script_dir}/../environments/prod"

terraform -chdir="${target_dir}" init -reconfigure \
  -backend-config="bucket=${TF_STATE_BUCKET}" \
  -backend-config="region=us-east-1"
