#!/usr/bin/env bash
set -euo pipefail

SCHEMA="infra/changelog/infra-changelog.schema.json"
CHANGELOG="infra/changelog/infra-changelog.jsonl"

die() { echo "❌ infra: $*" >&2; exit 1; }

command -v ajv >/dev/null 2>&1 \
  || die "ajv is required (npm install -g ajv-cli)"

[[ -f "$SCHEMA" ]] || die "missing schema: $SCHEMA"
[[ -f "$CHANGELOG" ]] || die "missing changelog: $CHANGELOG"

echo "🔎 Validating infra changelog (JSONL)..."

LINE_NO=0
while IFS= read -r line; do
  LINE_NO=$((LINE_NO + 1))

  [[ -n "$line" ]] || die "empty line at $LINE_NO"

  echo "$line" | ajv validate -s "$SCHEMA" -d /dev/stdin \
    || die "changelog schema violation at line $LINE_NO"
done < "$CHANGELOG"

echo "✅ Infra changelog valid"
