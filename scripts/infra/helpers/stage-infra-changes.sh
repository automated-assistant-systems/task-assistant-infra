#!/usr/bin/env bash
set -euo pipefail

REGISTRY="infra/telemetry-registry.v2.json"
CHANGELOG="infra/changelog/infra-changelog.jsonl"

git add "$REGISTRY" "$CHANGELOG"

echo "✓ staged infra registry and changelog"
