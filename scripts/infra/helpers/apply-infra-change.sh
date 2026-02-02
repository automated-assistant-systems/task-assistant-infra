#!/usr/bin/env bash
set -euo pipefail

# ============================================================
# apply-infra-change.sh
#
# Canonical operator entrypoint for infra mutations.
#
# Guarantees:
#   • infra.sh executed exactly once
#   • registry is mutated
#   • changelog is appended
#   • only allowed files are staged
#   • finalize-registry.sh passes
#
# Usage:
#   apply-infra-change.sh <infra.sh args...>
# ============================================================

ROOT_DIR="$(git rev-parse --show-toplevel)"
cd "$ROOT_DIR"

REGISTRY_FILE="$ROOT_DIR/infra/telemetry-registry.v2.json"
CHANGELOG_FILE="$ROOT_DIR/infra/changelog/infra-changelog.jsonl"

die() { echo "❌ infra: $*" >&2; exit 1; }
pass() { echo "✅ $*"; }

# ------------------------------------------------------------
# Preconditions
# ------------------------------------------------------------
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
[[ "$BRANCH" != "main" ]] || die "refusing to run on main"

[[ -z "$(git status --porcelain)" ]] || die "working tree must be clean"

[[ -f "$REGISTRY" ]] || die "missing $REGISTRY"
mkdir -p "$(dirname "$CHANGELOG")"
[[ -f "$CHANGELOG" ]] || touch "$CHANGELOG"

pass "Preconditions satisfied"

# ------------------------------------------------------------
# Snapshot BEFORE
# ------------------------------------------------------------
REG_BEFORE="$(sha256sum "$REGISTRY" | awk '{print $1}')"
LOG_LINES_BEFORE="$(wc -l < "$CHANGELOG")"

# ------------------------------------------------------------
# Execute infra mutation
# ------------------------------------------------------------
echo
echo "🚀 Running infra.sh $*"
echo

scripts/infra/infra.sh "$@"

# Re-anchor working directory (infra.sh may change CWD)
cd "$ROOT_DIR"

# ------------------------------------------------------------
# Postconditions (hard guarantees)
# ------------------------------------------------------------
REG_AFTER="$(sha256sum "$REGISTRY" | awk '{print $1}')"
LOG_LINES_AFTER="$(wc -l < "$CHANGELOG")"

[[ "$REG_BEFORE" != "$REG_AFTER" ]] \
  || die "registry was not modified"

[[ "$LOG_LINES_AFTER" -gt "$LOG_LINES_BEFORE" ]] \
  || die "infra changelog was NOT appended"

pass "Registry mutated and changelog appended"

# ------------------------------------------------------------
# Stage exactly what is allowed
# ------------------------------------------------------------
git add "$REGISTRY" "$CHANGELOG"

STAGED="$(git diff --cached --name-only)"

EXTRA_STAGED="$(echo "$STAGED" | grep -vE "^$REGISTRY$|^$CHANGELOG$" || true)"
[[ -z "$EXTRA_STAGED" ]] \
  || die "unexpected files staged: $EXTRA_STAGED"

pass "Only registry and changelog staged"

# ------------------------------------------------------------
# Final gate (authoritative)
# ------------------------------------------------------------
echo
echo "🔒 Running finalize-registry.sh"
scripts/infra/helpers/finalize-registry.sh

echo
echo "🎉 Infra change ready"
echo "Next:"
echo "  scripts/infra/helpers/commit-and-push-infra.sh \"infra: <change description>\""
echo "  scripts/infra/helpers/create-pr.sh"
echo "  scripts/infra/helpers/merge-pr.sh"
echo
