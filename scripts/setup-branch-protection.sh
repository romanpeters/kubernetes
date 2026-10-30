#!/usr/bin/env bash
set -euo pipefail

# Require the CI `validate` check before anything is merged into main.
#
# Why: Renovate is configured with `platformAutomerge: true` and automerges
# non-major Docker updates. Without a required status check GitHub merges those
# PRs immediately, so "after CI checks pass" is not actually enforced.
#
# Direct pushes to main stay allowed (no pull request requirement), so this only
# gates PR merges. Admin enforcement is off for the same reason.
#
# Usage: ./scripts/setup-branch-protection.sh
# Requires a token with admin rights on the repository.

REPO="${REPO:-$(gh repo view --json nameWithOwner --jq .nameWithOwner)}"
BRANCH="${BRANCH:-main}"
CHECK="${CHECK:-validate}"

info() { printf '  [info] %s\n' "$*"; }
ok() { printf '  [ ok ] %s\n' "$*"; }

info "repository: ${REPO}, branch: ${BRANCH}, required check: ${CHECK}"

result=$(gh api -X PUT "repos/${REPO}/branches/${BRANCH}/protection" --input - <<JSON
{
  "required_status_checks": {
    "strict": false,
    "contexts": ["${CHECK}"]
  },
  "enforce_admins": false,
  "required_pull_request_reviews": null,
  "restrictions": null,
  "allow_force_pushes": false,
  "allow_deletions": false
}
JSON
)

contexts=$(printf '%s' "$result" | jq -c '.required_status_checks.contexts')
ok "${BRANCH} requires ${contexts} before merge (direct pushes unaffected)"
