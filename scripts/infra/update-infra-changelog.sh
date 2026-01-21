#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-generate}"

REGISTRY_FILE="infra/telemetry-registry.v2.json"
CHANGELOG_DIR="infra/changelog"
CHANGELOG_FILE="${CHANGELOG_DIR}/infra-changelog.jsonl"

BASE_REF="origin/main"
HEAD_REF="HEAD"

mkdir -p "${CHANGELOG_DIR}"
touch "${CHANGELOG_FILE}"

echo "🔎 Infra changelog (${MODE})"

# ─────────────────────────────────────────────
# Detect registry changes
# ─────────────────────────────────────────────
if [[ "${MODE}" == "--check" ]]; then
  # CI mode: compare commits
  if git diff --quiet "${BASE_REF}...${HEAD_REF}" -- "${REGISTRY_FILE}"; then
    echo "ℹ️ No registry changes detected"
    exit 0
  fi
else
  # Generate mode: compare working tree
  if git diff --quiet -- "${REGISTRY_FILE}"; then
    echo "ℹ️ No registry changes detected"
    exit 0
  fi
fi

# In check mode, require changelog update
if [[ "${MODE}" == "--check" ]]; then
  if git diff --quiet "${BASE_REF}...${HEAD_REF}" -- "${CHANGELOG_FILE}"; then
    echo "❌ Registry changed but infra changelog not updated"
    exit 1
  fi

  echo "✅ Registry change has matching changelog entry"
  exit 0
fi

# ─────────────────────────────────────────────
# Generate changelog entries
# ─────────────────────────────────────────────
echo "📝 Generating infra changelog entries"

git show "${BASE_REF}:${REGISTRY_FILE}" > /tmp/registry.before.json 2>/dev/null || echo '{}' > /tmp/registry.before.json
git show "${HEAD_REF}:${REGISTRY_FILE}" > /tmp/registry.after.json

jq '.' /tmp/registry.before.json > /tmp/registry.before.norm.json
jq '.' /tmp/registry.after.json  > /tmp/registry.after.norm.json

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
ACTOR="$(git log -1 --pretty=format:%an)"

# ─── Register / Disable ──────────────────────
jq -r '
  .orgs // {} | to_entries[] |
  .key as $org |
  (.value.repos // {}) | to_entries[] |
  "\($org) \(.key) \(.value.state)"
' /tmp/registry.after.norm.json | while read -r ORG REPO STATE; do

  PREV_STATE="$(jq -r --arg org "$ORG" --arg repo "$REPO" \
    '.orgs[$org].repos[$repo].state // "absent"' \
    /tmp/registry.before.norm.json)"

  ACTION=""

  if [[ "$PREV_STATE" == "absent" && "$STATE" == "enabled" ]]; then
    ACTION="register"
  elif [[ "$PREV_STATE" == "enabled" && "$STATE" == "disabled" ]]; then
    ACTION="disable"
  fi

  if [[ -n "$ACTION" ]]; then
    jq -n \
      --arg ts "$TIMESTAMP" \
      --arg actor "$ACTOR" \
      --arg process "infra-cli" \
      --arg action "$ACTION" \
      --arg context "sandbox" \
      --arg org "$ORG" \
      --arg repo "$REPO" \
      '{
        timestamp: $ts,
        actor: $actor,
        process: $process,
        action: $action,
        context: $context,
        org: $org,
        repo: $repo
      }' >> "${CHANGELOG_FILE}"
  fi
done

# ─── Delete ──────────────────────────────────
jq -r '
  .orgs // {} | to_entries[] |
  .key as $org |
  (.value.repos // {}) | keys[] |
  "\($org) \(.)"
' /tmp/registry.before.norm.json | while read -r ORG REPO; do

  EXISTS_AFTER="$(jq -r --arg org "$ORG" --arg repo "$REPO" \
    '.orgs[$org].repos[$repo] // empty' \
    /tmp/registry.after.norm.json)"

  if [[ -z "$EXISTS_AFTER" ]]; then
    jq -n \
      --arg ts "$TIMESTAMP" \
      --arg actor "$ACTOR" \
      --arg process "infra-cli" \
      --arg action "delete" \
      --arg context "sandbox" \
      --arg org "$ORG" \
      --arg repo "$REPO" \
      '{
        timestamp: $ts,
        actor: $actor,
        process: $process,
        action: $action,
        context: $context,
        org: $org,
        repo: $repo
      }' >> "${CHANGELOG_FILE}"
  fi
done

echo "✅ Infra changelog entries generated"
