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

  PRS="$(gh pr list --head "$CURRENT_BRANCH" --json number,title)"

  COUNT="$(echo "$PRS" | jq 'length')"

  if [[ "$COUNT" -eq 0 ]]; then
    echo "❌ No open PR found for branch '$CURRENT_BRANCH'"
    exit 1
  fi

  if [[ "$COUNT" -gt 1 ]]; then
    echo "❌ Multiple PRs found for branch '$CURRENT_BRANCH'"
    echo "$PRS" | jq -r '.[] | "• #\(.number): \(.title)"'
    exit 1
  fi

  PR_NUMBER="$(echo "$PRS" | jq -r '.[0].number')"
  PR_TITLE="$(echo "$PRS" | jq -r '.[0].title')"
else
  PR_TITLE="$(gh pr view "$PR_NUMBER" --json title --jq '.title')"
fi

echo "🔀 Ready to merge PR #$PR_NUMBER"
echo "• Title: $PR_TITLE"
echo

read -r -p "Type 'merge' to confirm: " CONFIRM

if [[ "$CONFIRM" != "merge" ]]; then
  echo "❌ Aborted"
  exit 1
fi

gh pr merge "$PR_NUMBER" --squash --delete-branch
