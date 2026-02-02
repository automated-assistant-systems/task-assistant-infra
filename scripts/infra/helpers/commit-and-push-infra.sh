#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# commit-and-push-infra.sh
#
# Purpose:
#   Perform the irreversible transport step:
#   commit + push an already-finalized infra change.
#
# Preconditions (ENFORCED):
#   • Not on main
#   • Working tree clean
#   • Registry staged
#   • Changelog staged
#   • No other files staged
#
# This script:
#   • DOES NOT mutate infra
#   • DOES NOT validate schema
#   • DOES NOT open a PR
# ─────────────────────────────────────────────

REGISTRY="infra/telemetry-registry.v2.json"
CHANGELOG="infra/changelog/infra-changelog.jsonl"

die() {
  echo "❌ infra: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

need_cmd git

# ─────────────────────────────────────────────
# Branch guard
# ─────────────────────────────────────────────
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$BRANCH" != "main" ]] || die "refusing to commit infra on main"

# ─────────────────────────────────────────────
# Working tree must be clean
# ─────────────────────────────────────────────
git diff --quiet || die "working tree has unstaged changes"

# ─────────────────────────────────────────────
# Staging guards
# ─────────────────────────────────────────────
STAGED="$(git diff --cached --name-only)"

echo "$STAGED" | grep -qx "$REGISTRY" \
  || die "registry not staged: $REGISTRY"

echo "$STAGED" | grep -qx "$CHANGELOG" \
  || die "changelog not staged: $CHANGELOG"

EXTRA="$(echo "$STAGED" | grep -v -E "^($REGISTRY|$CHANGELOG)$" || true)"
[[ -z "$EXTRA" ]] || die "unexpected files staged:\n$EXTRA"

# ─────────────────────────────────────────────
# Commit message
# ─────────────────────────────────────────────
MSG="${1:-}"

if [[ -z "$MSG" ]]; then
  echo
  echo "Enter infra commit message:"
  read -r MSG
fi

[[ -n "$MSG" ]] || die "commit message required"

# ─────────────────────────────────────────────
# Commit + push
# ─────────────────────────────────────────────
git commit -m "$MSG"
git push -u origin "$BRANCH"

echo
echo "✅ Infra committed and pushed"
echo "• Branch: $BRANCH"
echo "• Commit: $MSG"
echo
echo "Next step:"
echo "  scripts/infra/helpers/create-pr.sh"
