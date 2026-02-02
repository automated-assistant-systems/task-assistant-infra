#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# abort-infra-change.sh
#
# Emergency abort for infra registry operations.
#
# Effects:
#   • Discards ALL uncommitted changes
#   • Switches back to main
#   • Deletes the current branch
#   • Deletes the remote branch if it exists
#
# Safe-guards:
#   • Refuses to run on main
# ============================================================

die() { echo "❌ infra-abort: $*" >&2; exit 1; }
info() { echo "ℹ️  $*"; }
pass() { echo "✅ $*"; }

CURRENT_BRANCH="$(git rev-parse --abbrev-ref HEAD)"

[[ "$CURRENT_BRANCH" != "main" ]] \
  || die "refusing to abort while on main"

info "Aborting infra change on branch: $CURRENT_BRANCH"

# ------------------------------------------------------------
# Hard reset local state
# ------------------------------------------------------------
info "Discarding working tree changes"
git reset --hard

# ------------------------------------------------------------
# Switch back to main
# ------------------------------------------------------------
info "Switching to main"
git checkout main

# ------------------------------------------------------------
# Delete local branch
# ------------------------------------------------------------
info "Deleting local branch: $CURRENT_BRANCH"
git branch -D "$CURRENT_BRANCH"

# ------------------------------------------------------------
# Delete remote branch if it exists
# ------------------------------------------------------------
if git ls-remote --exit-code --heads origin "$CURRENT_BRANCH" >/dev/null 2>&1; then
  info "Deleting remote branch: origin/$CURRENT_BRANCH"
  git push origin --delete "$CURRENT_BRANCH"
else
  info "No remote branch to delete"
fi

pass "Infra abort complete"
echo
echo "Repository state:"
git status
