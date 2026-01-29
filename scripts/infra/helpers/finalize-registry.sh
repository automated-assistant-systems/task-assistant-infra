#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# finalize-registry.sh
#
# Purpose:
#   Final safety gate before infra PR creation.
#   Validates, enforces, and stages registry changes.
#
# Aligned with:
#   README.md (Infra v2 authoritative rules)
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
# Dirty tree check
# ─────────────────────────────────────────────
git diff --quiet || die "working tree has unstaged changes"
git diff --cached --quiet || true

# Registry must be modified
git diff --name-only | grep -q "^$REGISTRY$" \
  || die "registry file not modified: $REGISTRY"

# No other files allowed
EXTRA_CHANGES="$(git diff --name-only | grep -v "^$REGISTRY$" || true)"
[[ -z "$EXTRA_CHANGES" ]] || die "only $REGISTRY may be modified"

# ─────────────────────────────────────────────
# Schema validation
# ─────────────────────────────────────────────
[[ -x scripts/infra/validate-registry-v2.sh ]] \
  || die "missing validate-registry-v2.sh"

echo "🔎 Validating telemetry registry (v2)..."
scripts/infra/validate-registry-v2.sh

# ─────────────────────────────────────────────
# Explicit context enforcement
# ─────────────────────────────────────────────
echo "🔒 Enforcing explicit repo context..."

jq -e '
  .orgs
  | to_entries[]
  | .value.repos
  | to_entries[]
  | select(.value.context != "sandbox" and .value.context != "production")
' "$REGISTRY" >/dev/null && die "repo missing valid context (sandbox|production)"

# ─────────────────────────────────────────────
# Cross-org telemetry enforcement
# ─────────────────────────────────────────────
echo "🛑 Enforcing per-org telemetry isolation..."

jq -e '
  .orgs
  | to_entries[]
  | .key as $org
  | .value.telemetry_repo as $telemetry
  | select($telemetry != null)
  | select($telemetry | startswith($org + "/") | not)
' "$REGISTRY" >/dev/null && die "cross-org telemetry detected"

# ─────────────────────────────────────────────
# Stage registry
# ─────────────────────────────────────────────
git add "$REGISTRY"

echo
echo "✅ Infra registry finalized"
echo "• Branch:  $CURRENT_BRANCH"
echo "• File:    $REGISTRY"
echo
echo "Next steps:"
echo "  scripts/infra/helpers/create-pr.sh"
