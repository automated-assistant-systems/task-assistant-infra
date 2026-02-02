#!/usr/bin/env bash
set -euo pipefail

# ---------------------------------------------
# Create a new infra working branch safely
#
# Usage:
#   new-branch.sh <branch-name>
#
# Rules:
#   - Must be on a named branch (no detached HEAD)
#   - Working tree must be clean
#   - Branch must not already exist
#   - Running on main is ALLOWED (and expected)
# ---------------------------------------------

BRANCH="${1:-}"

if [[ -z "$BRANCH" ]]; then
  echo "usage: new-branch.sh <branch-name>" >&2
  exit 1
fi

current_branch="$(git branch --show-current)"

[[ -n "$current_branch" ]] || {
  echo "❌ detached HEAD; checkout a branch first" >&2
  exit 1
}

git diff --quiet || {
  echo "❌ working tree not clean" >&2
  exit 1
}

git diff --cached --quiet || {
  echo "❌ index not clean" >&2
  exit 1
}

if git show-ref --verify --quiet "refs/heads/$BRANCH"; then
  echo "❌ branch already exists: $BRANCH" >&2
  exit 1
fi

git checkout -b "$BRANCH"
echo "✓ created and switched to branch: $BRANCH"
echo
echo "Next Steps"
echo "    scripts/infra/helpers/apply-infra-change.sh {...}"
echo "    scripts/infra/helpers/commit-and-push-infra.sh \"infra: description\""
echo "    scripts/infra/helpers/create-pr.sh"
echo "    scripts/infra/helpers/merge.sh"
echo
