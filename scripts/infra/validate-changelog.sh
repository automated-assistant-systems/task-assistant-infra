#!/usr/bin/env bash
set -euo pipefail

CHANGELOG="infra/changelog/infra-changelog.jsonl"

die() { echo "❌ infra: $*" >&2; exit 1; }

command -v jq >/dev/null 2>&1 || die "jq is required"

[[ -f "$CHANGELOG" ]] || die "missing $CHANGELOG"

echo "🔎 Validating infra changelog (jq)"

LINE_NO=0

while IFS= read -r line; do
  LINE_NO=$((LINE_NO + 1))
  [[ -n "$line" ]] || die "empty line at $LINE_NO"

  echo "$line" | jq -e '
    type == "object" and
    .timestamp and
    .action and
    .owner and
    .repo and
    .process == "infra-cli" and
    .schema_version == "2.0" and
    (.action | IN("register","disable","unregister")) and
    (
      (has("context") | not) or
      (.context | IN("sandbox","production"))
    ) and
    (
      (has("telemetry_repo") | not) or
      (.telemetry_repo | type == "string" and length > 0)
    ) and
    (
      (has("reason") | not) or
      (.reason | type == "string" and length > 0)
    )
  ' >/dev/null || die "invalid changelog entry at line $LINE_NO"

done < "$CHANGELOG"

echo "✅ Infra changelog valid"
