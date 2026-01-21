#!/usr/bin/env bash
set -euo pipefail

REGISTRY_FILE="infra/telemetry-registry.v2.json"

echo "🔎 Validating telemetry registry (v2)..."

[[ -f "$REGISTRY_FILE" ]] || { echo "❌ Missing $REGISTRY_FILE"; exit 1; }

SCHEMA_VERSION=$(jq -r '.schema_version // empty' "$REGISTRY_FILE")
[[ "$SCHEMA_VERSION" == 2.* ]] || {
  echo "❌ Expected schema_version 2.x, got: ${SCHEMA_VERSION:-<missing>}"
  exit 1
}

jq -e '.orgs | type == "object"' "$REGISTRY_FILE" >/dev/null || {
  echo "❌ v2 registry must contain top-level object: orgs"
  exit 1
}

echo "✅ v2 registry schema valid"
