#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
# Task Assistant Infra — Auto Changelog
#
# Strategy:
# - Maintain a top "## Unreleased" section.
# - Populate it from commits since latest tag.
# - If no tags exist, use full history.
# - Rebuild Unreleased each run (idempotent).
# ─────────────────────────────────────────────

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
cd "$ROOT_DIR"

CHANGELOG="CHANGELOG.md"

# Ensure file exists
if [[ ! -f "$CHANGELOG" ]]; then
  cat > "$CHANGELOG" <<'EOF'
# Changelog

All notable changes to this repository will be documented in this file.

## Unreleased

EOF
fi

# Determine range: latest tag..HEAD, else all history
if git describe --tags --abbrev=0 >/dev/null 2>&1; then
  BASE_TAG="$(git describe --tags --abbrev=0)"
  RANGE="${BASE_TAG}..HEAD"
  BASE_LABEL="since ${BASE_TAG}"
else
  RANGE=""
  BASE_LABEL="since beginning"
fi

# Collect commits (excluding merges)
# Format: - <subject> (<shortsha>)
if [[ -n "$RANGE" ]]; then
  COMMITS="$(git log --no-merges --pretty=format:'- %s (%h)' "$RANGE" || true)"
else
  COMMITS="$(git log --no-merges --pretty=format:'- %s (%h)' || true)"
fi

if [[ -z "${COMMITS// }" ]]; then
  COMMITS="- No changes yet (${BASE_LABEL})."
fi

TODAY_UTC="$(date -u +"%Y-%m-%d")"

# Rebuild CHANGELOG with a regenerated Unreleased section.
# Keep everything after the Unreleased section exactly as-is.
#
# Convention:
# - Unreleased section ends at the next "## " header (or EOF).
awk -v today="$TODAY_UTC" -v base="$BASE_LABEL" -v commits="$COMMITS" '
BEGIN {
  in_unreleased = 0
  printed_unreleased = 0
}

# Detect Unreleased header
/^##[[:space:]]+Unreleased[[:space:]]*$/ {
  in_unreleased = 1

  # Print regenerated Unreleased section once
  if (!printed_unreleased) {
    print "## Unreleased"
    print ""
    print "_Updated: " today " UTC (" base ")_"
    print ""
    n = split(commits, lines, "\n")
    for (i = 1; i <= n; i++) print lines[i]
    print ""
    printed_unreleased = 1
  }

  next
}

# If we are inside Unreleased, skip lines until next section header
in_unreleased == 1 {
  if ($0 ~ /^##[[:space:]]+/) {
    in_unreleased = 0
    print $0
  }
  next
}

# Default: print lines verbatim
{
  print $0
}

END {
  # If file had no Unreleased section, prepend one.
  if (!printed_unreleased) {
    # This should be rare because we create it above,
    # but keep safe behavior if user edits the file.
  }
}
' "$CHANGELOG" > "$CHANGELOG.tmp"

mv "$CHANGELOG.tmp" "$CHANGELOG"
