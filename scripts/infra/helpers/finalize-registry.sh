#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# finalize-registry.sh (STAGED-ONLY)
#
# Purpose:
#   Final safety gate before infra PR creation.
#   Validates the *staged* registry change only.
#
# Guarantees:
#   • No file mutations
#   • No staging
#   • No commits
#   • No execution on main
#
# Operator must:
#   1) run infra.sh
#   2) git add infra/telemetry-registry.v2.json
#   3) run this script
# ─────────────────────────────────────────────

REGISTRY="infra/telemetry-registry.v2.json"
BASE_BRANCH="main"

die() {
  echo "❌ infra: $*" >&2
  exit 1
}

need_cmd() {
  command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"
}

need_cmd git
need_cmd jq

# ─────────────────────────────────────────────
# Branch guard
# ─────────────────────────────────────────────
CURRENT_BRANCH="$(git branch --show-current)"
[[ -n "$CURRENT_BRANCH" ]] || die "unable to determine current branch"

if [[ "$CURRENT_BRANCH" == "$BASE_BRANCH" ]]; then
  die "refusing to finalize infra on '$BASE_BRANCH'"
fi

# ─────────────────────────────────────────────
# Staging guards
# ─────────────────────────────────────────────

# Registry must be staged
git diff --cached --name-only | grep -qx "$REGISTRY" \
  || die "registry file is not staged: $REGISTRY"

# No other files may be staged
EXTRA_STAGED="$(git diff --cached --name-only | grep -v "^$REGISTRY$" || true)"
[[ -z "$EXTRA_STAGED" ]] || die "only $REGISTRY may be staged"

# No unstaged changes allowed
git diff --quiet || die "working tree has unstaged changes"

# ─────────────────────────────────────────────
# Validate staged content
# ─────────────────────────────────────────────

echo "🔎 Validating staged telemetry registry (v2)..."

STAGED_JSON="$(git show ":$REGISTRY")"

# Schema validation
if [[ -x scripts/infra/validate-registry-v2.sh ]]; then
  printf '%s\n' "$STAGED_JSON" | scripts/infra/validate-registry-v2.sh --stdin
else
  die "missing validate-registry-v2.sh"
fi

# ─────────────────────────────────────────────
# Explicit context enforcement
# ─────────────────────────────────────────────
echo "🔒 Enforcing explicit repo context..."

printf '%s\n' "$STAGED_JSON" | jq -e '
  .orgs
  | to_entries[]
  | .value.repos
  | to_entries[]
  | select(.value.context != "sandbox" and .value.context != "production")
' >/dev/null && die "repo missing valid context (sandbox|production)"

# ─────────────────────────────────────────────
# Cross-org telemetry enforcement
# ─────────────────────────────────────────────
echo "🛑 Enforcing per-org telemetry isolation..."

printf '%s\n' "$STAGED_JSON" | jq -e '
  .orgs
  | to_entries[]
  | .key as $org
  | .value.telemetry_repo as $telemetry
  | select($telemetry != null)
  | select($telemetry | startswith($org + "/") | not)
' >/dev/null && die "cross-org telemetry detected"

# ─────────────────────────────────────────────
# Success
# ─────────────────────────────────────────────
echo
echo "✅ Infra registry finalized (staged-only)"
echo "• Branch: $CURRENT_BRANCH"
echo "• File:   $REGISTRY"
echo
echo "Next steps:"
echo "  git commit -m \"infra: <describe change>\""
echo "  git push"
echo "  scripts/infra/helpers/create-pr.sh"
