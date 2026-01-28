#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# merge-pr.sh
#
# Merge a PR safely via gh.
#
# Usage:
#   merge-pr.sh <pr-number>
#   merge-pr.sh   # merges PR for current branch
# ─────────────────────────────────────────────

source "$(dirname "$0")/_guard.sh"

if ! command -v gh >/dev/null; then
  echo "❌ gh CLI is required"
  exit 1
fi

PR_NUMBER="${1:-}"

if [[ -z "$PR_NUMBER" ]]; then
  CURRENT_BRANCH="$(git branch --show-current)"
  [[ -n "$CURRENT_BRANCH" ]] || {
    echo "❌ Unable to determine current branch"
    exit 1
  }

  PR_NUMBER="$(
    gh pr list \
      --head "$CURRENT_BRANCH" \
      --json number \
      --jq '.[0].number' || true
  )"

  [[ -n "$PR_NUMBER" ]] || {
    echo "❌ No open PR found for branch '$CURRENT_BRANCH'"
    exit 1
  }
fi

echo "🔀 Merging PR #$PR_NUMBER"
echo

gh pr merge "$PR_NUMBER" --squash --delete-branch
