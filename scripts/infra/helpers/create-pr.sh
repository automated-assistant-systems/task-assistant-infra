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

source "$(dirname "$0")/_guard.sh"

BASE_BRANCH="main"

CURRENT_BRANCH="$(git branch --show-current)"

if [[ -z "$CURRENT_BRANCH" ]]; then
  echo "❌ Unable to determine current branch"
  exit 1
fi

if [[ "$CURRENT_BRANCH" == "$BASE_BRANCH" ]]; then
  echo "❌ Refusing to create PR from '$BASE_BRANCH'"
  echo "   Create a feature branch first."
  exit 1
fi

if ! git diff --quiet || ! git diff --cached --quiet; then
  echo "❌ Working tree is dirty"
  echo "   Commit or stash changes before creating a PR."
  exit 1
fi

if ! command -v gh >/dev/null; then
  echo "❌ gh CLI is required"
  exit 1
fi

echo "📦 Creating PR"
echo "• Branch: $CURRENT_BRANCH"
echo "• Base:   $BASE_BRANCH"
echo

gh pr create --base "$BASE_BRANCH"
