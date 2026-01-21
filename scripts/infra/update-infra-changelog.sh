#!/usr/bin/env bash
set -euo pipefail

REGISTRY_FILE="infra/telemetry-registry.json"
CHANGELOG_DIR="infra/changelog"
CHANGELOG_FILE="${CHANGELOG_DIR}/infra-changelog.jsonl"

# Ensure expected paths exist
mkdir -p "${CHANGELOG_DIR}"
touch "${CHANGELOG_FILE}"

# Identify last commit that modified the registry
LAST_COMMIT="$(git log -n 1 --pretty=format:%H -- "${REGISTRY_FILE}" || true)"

# Nothing to do if registry not touched in this push
if [[ -z "${LAST_COMMIT}" ]]; then
  echo "No registry changes detected"
  exit 0
fi

# Compare previous version
PREV_COMMIT="${LAST_COMMIT}~1"

echo "Processing registry change at ${LAST_COMMIT}"

# Extract before / after registry snapshots
git show "${PREV_COMMIT}:${REGISTRY_FILE}" > /tmp/registry.before.json 2>/dev/null || echo "{}" > /tmp/registry.before.json
git show "${LAST_COMMIT}:${REGISTRY_FILE}" > /tmp/registry.after.json

# Normalize JSON (defensive)
jq '.' /tmp/registry.before.json > /tmp/registry.before.norm.json
jq '.' /tmp/registry.after.json > /tmp/registry.after.norm.json

TIMESTAMP="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"
ACTOR="$(git log -n 1 --pretty=format:%an "${LAST_COMMIT}")"

# Iterate repos in AFTER state
jq -r '.orgs | to_entries[] | .key as $org | .value.repos | to_entries[] | "\($org) \(.key) \(.value.state)"' \
  /tmp/registry.after.norm.json | while read -r ORG REPO STATE; do

    PREV_STATE="$(jq -r --arg org "$ORG" --arg repo "$REPO" \
      '.orgs[$org].repos[$repo].state // "absent"' \
      /tmp/registry.before.norm.json)"

    ACTION=""

    if [[ "${PREV_STATE}" == "absent" && "${STATE}" == "enabled" ]]; then
      ACTION="register"
    elif [[ "${PREV_STATE}" == "enabled" && "${STATE}" == "disabled" ]]; then
      ACTION="disable"
    fi

    if [[ -n "${ACTION}" ]]; then
      jq -n \
        --arg ts "${TIMESTAMP}" \
        --arg actor "${ACTOR}" \
        --arg action "${ACTION}" \
        --arg process "infra-cli" \
        --arg context "sandbox" \
        --arg org "${ORG}" \
        --arg repo "${REPO}" \
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

# Detect deletes (present before, missing after)
jq -r '.orgs | to_entries[] | .key as $org | .value.repos | keys[] | "\($org) \(.)"' \
  /tmp/registry.before.norm.json | while read -r ORG REPO; do

    EXISTS_AFTER="$(jq -r --arg org "$ORG" --arg repo "$REPO" \
      '.orgs[$org].repos[$repo] // empty' \
      /tmp/registry.after.norm.json)"

    if [[ -z "${EXISTS_AFTER}" ]]; then
      jq -n \
        --arg ts "${TIMESTAMP}" \
        --arg actor "${ACTOR}" \
        --arg action "delete" \
        --arg process "infra-cli" \
        --arg context "sandbox" \
        --arg org "${ORG}" \
        --arg repo "${REPO}" \
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

echo "Infra changelog updated successfully"
