#!/usr/bin/env bash
# Applies `main` branch protection for this repo via `gh api`. USER-RUN
# ONLY -- never invoked by any workflow in `.github/workflows/`.
#
# Run this once, after CI has gone green at least once on a PR (a status
# check's name can only be required once GitHub has seen it appear).
#
# Usage:
#   ./scripts/setup-branch-protection.sh
set -euo pipefail

# The repo this script is meant to protect. Override only if this repo is
# renamed or forked -- must match bootstrap/variables.tf's github_org/
# github_repo defaults (the OIDC trust policies are scoped to this string).
EXPECTED_REPO="${EXPECTED_REPO:-estanixx/effective-sia-spoon}"
BRANCH="main"
REQUIRED_CHECKS=("ci / fmt" "ci / validate" "ci / tflint" "ci / checkov" "ci / image" "plan")

# Never let CI run this. Branch protection is a one-time, human-run action.
if [ -n "${CI:-}" ]; then
  echo "error: refusing to run in CI. This script is user-run only." >&2
  exit 1
fi

if ! command -v gh >/dev/null 2>&1; then
  echo "error: gh CLI not found. Install and authenticate it first (gh auth login)." >&2
  exit 1
fi

if ! command -v jq >/dev/null 2>&1; then
  echo "error: jq not found. Install it (used to build the gh api request body)." >&2
  exit 1
fi

# Resolve the actual target repo from the current gh context (git remote /
# `gh` auth), never assume. This is the one guard against silently
# targeting the wrong repo from the wrong working directory.
resolved_repo="$(gh repo view --json nameWithOwner -q .nameWithOwner)"

if [ "${resolved_repo}" != "${EXPECTED_REPO}" ]; then
  echo "warning: resolved repo '${resolved_repo}' does not match expected '${EXPECTED_REPO}'." >&2
  read -r -p "Proceed and apply branch protection to '${resolved_repo}' anyway? [y/N] " confirm_mismatch
  case "${confirm_mismatch}" in
    y | Y | yes | YES) : ;;
    *)
      echo "Aborted: repo mismatch not confirmed." >&2
      exit 1
      ;;
  esac
fi

echo "About to apply branch protection to:"
echo "  repo:   ${resolved_repo}"
echo "  branch: ${BRANCH}"
echo
echo "Settings:"
echo "  - No direct pushes; pull request required"
echo "  - Required approving reviews: 1"
echo "  - Required status checks (strict, must be up to date with base branch):"
for check in "${REQUIRED_CHECKS[@]}"; do
  echo "      - ${check}"
done
echo "  - Enforce on admins: false (documented choice below)"
echo "  - Force pushes: disallowed"
echo "  - Branch deletion: disallowed"
echo
echo "Rationale for enforce_admins=false: this repo has a single admin;"
echo "leaving admins able to bypass protection preserves a manual escape"
echo "hatch for incident recovery (e.g. a required check misnamed and"
echo "blocking every PR). Flip to true later via the GitHub UI or a re-run"
echo "with the body edited below once more than one maintainer exists."
echo

read -r -p "Continue? [y/N] " confirm
case "${confirm}" in
  y | Y | yes | YES) : ;;
  *)
    echo "Aborted: no changes made." >&2
    exit 1
    ;;
esac

# Build the required_status_checks.checks array as JSON.
checks_json="[]"
for check in "${REQUIRED_CHECKS[@]}"; do
  checks_json="$(printf '%s' "${checks_json}" | jq --arg ctx "${check}" '. + [{"context": $ctx}]')"
done

request_body="$(
  jq -n \
    --argjson checks "${checks_json}" \
    '{
      required_status_checks: {
        strict: true,
        checks: $checks
      },
      enforce_admins: false,
      required_pull_request_reviews: {
        required_approving_review_count: 1,
        dismiss_stale_reviews: true
      },
      restrictions: null,
      required_linear_history: false,
      allow_force_pushes: false,
      allow_deletions: false
    }'
)"

GH_REPO="${resolved_repo}" gh api \
  --method PUT \
  -H "Accept: application/vnd.github+json" \
  "repos/{owner}/{repo}/branches/${BRANCH}/protection" \
  --input - <<<"${request_body}"

echo
echo "Branch protection applied to ${resolved_repo}@${BRANCH}."

echo
echo "Also enabling delete-branch-on-merge (separate endpoint, not part of"
echo "the protection payload above)..."
gh api --method PATCH "repos/${resolved_repo}" -f delete_branch_on_merge=true >/dev/null
echo "Done."
