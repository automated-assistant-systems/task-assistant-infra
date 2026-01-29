#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# create-pr.sh
#
# Safe helper to create a GitHub PR from
# the current branch.
#
# Refuses:
#   • main / default branch
#   • dirty working tree
# ─────────────────────────────────────────────

BASE_BRANCH="main"

CURRENT_BRANCH="$(git branch --show-current)"

[[ -n "$CURRENT_BRANCH" ]] || {
  echo "❌ Unable to determine current branch"
  exit 1
}

if [[ "$CURRENT_BRANCH" == "$BASE_BRANCH" ]]; then
  echo "❌ Refusing to create PR from '$BASE_BRANCH'"
  exit 1
fi

git diff --quiet && git diff --cached --quiet || {
  echo "❌ Working tree is dirty"
  exit 1
}

if ! git rev-parse --verify "$BASE_BRANCH" >/dev/null 2>&1; then
  echo "❌ Base branch '$BASE_BRANCH' does not exist locally"
  exit 1
fi

COMMITS_AHEAD="$(git rev-list --count "$BASE_BRANCH..HEAD")"

if [[ "$COMMITS_AHEAD" -eq 0 ]]; then
  echo "❌ No commits to merge into $BASE_BRANCH"
  echo "   Did you forget to commit?"
  exit 1
fi

command -v gh >/dev/null || {
  echo "❌ gh CLI is required"
  exit 1
}

echo "📦 Creating PR"
echo "• Branch: $CURRENT_BRANCH"
echo "• Base:   $BASE_BRANCH"
echo "• Commits ahead: $COMMITS_AHEAD"
echo

gh pr create --base "$BASE_BRANCH"
