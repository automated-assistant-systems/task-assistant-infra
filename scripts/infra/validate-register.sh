#!/usr/bin/env bash
set -euo pipefail

REGISTRY="telemetry-registry.json"

echo "🔎 Validating telemetry registry..."
echo

# ------------------------------------------------------------
# Basic file sanity
# ------------------------------------------------------------
[[ -f "$REGISTRY" ]] || {
  echo "❌ Missing $REGISTRY"
  exit 1
}

jq . "$REGISTRY" >/dev/null || {
  echo "❌ Registry is not valid JSON"
  exit 1
}

# ------------------------------------------------------------
# Required top-level keys
# ------------------------------------------------------------
for key in schema_version organizations rules; do
  jq -e ".${key}" "$REGISTRY" >/dev/null || {
    echo "❌ Missing top-level key: $key"
    exit 1
  }
done

# ------------------------------------------------------------
# Organization validation
# ------------------------------------------------------------
ORG_COUNT="$(jq '.organizations | length' "$REGISTRY")"
[[ "$ORG_COUNT" -gt 0 ]] || {
  echo "❌ No organizations defined"
  exit 1
}

# Unique owners
DUP_ORGS="$(jq -r '.organizations[].owner' "$REGISTRY" | sort | uniq -d)"
if [[ -n "$DUP_ORGS" ]]; then
  echo "❌ Duplicate org owners:"
  echo "$DUP_ORGS"
  exit 1
fi

# ------------------------------------------------------------
# Per-org validation
# ------------------------------------------------------------
jq -c '.organizations[]' "$REGISTRY" | while read -r org; do
  OWNER="$(jq -r '.owner' <<< "$org")"
  TELEMETRY_REPO="$(jq -r '.telemetry_repo' <<< "$org")"

  echo "→ Validating org: $OWNER"

  # telemetry_repo must match owner
  if [[ "$TELEMETRY_REPO" != "$OWNER/"* ]]; then
    echo "❌ telemetry_repo must be owner-scoped: $TELEMETRY_REPO"
    exit 1
  fi

  # dashboard block required
  jq -e '.dashboard.enabled' <<< "$org" >/dev/null || {
    echo "❌ Missing dashboard.enabled for $OWNER"
    exit 1
  }

  # repositories must exist
  jq -e '.repositories | length > 0' <<< "$org" >/dev/null || {
    echo "❌ No repositories listed for $OWNER"
    exit 1
  }

  # repo name uniqueness
  DUP_REPOS="$(jq -r '.repositories[].name' <<< "$org" | sort | uniq -d)"
  if [[ -n "$DUP_REPOS" ]]; then
    echo "❌ Duplicate repo names in $OWNER:"
    echo "$DUP_REPOS"
    exit 1
  fi

  # enabled must be boolean
  jq -e '.repositories[].enabled | type == "boolean"' <<< "$org" >/dev/null || {
    echo "❌ Non-boolean enabled flag in $OWNER repositories"
    exit 1
  }

done

# ------------------------------------------------------------
# Cross-org repo collision detection
# ------------------------------------------------------------
ALL_REPOS="$(jq -r '.organizations[].repositories[].name' "$REGISTRY")"
DUP_GLOBAL="$(echo "$ALL_REPOS" | sort | uniq -d)"

if [[ -n "$DUP_GLOBAL" ]]; then
  echo "❌ Repository name collision across orgs:"
  echo "$DUP_GLOBAL"
  echo "Repo names must be unique per org, not reused across orgs"
  exit 1
fi

# ------------------------------------------------------------
# Rules enforcement
# ------------------------------------------------------------
DISCOVERY="$(jq -r '.rules.discovery' "$REGISTRY")"
[[ "$DISCOVERY" == "explicit-only" ]] || {
  echo "❌ rules.discovery must be explicit-only"
  exit 1
}

MUTATION="$(jq -r '.rules.mutation_allowed' "$REGISTRY")"
[[ "$MUTATION" == "false" ]] || {
  echo "❌ rules.mutation_allowed must be false"
  exit 1
}

# ------------------------------------------------------------
# Dashboard eligibility checks
# ------------------------------------------------------------
jq -c '.organizations[] | select(.dashboard.enabled == true)' "$REGISTRY" \
  | while read -r org; do
      OWNER="$(jq -r '.owner' <<< "$org")"

      ENABLED_REPOS="$(jq -r '.repositories[] | select(.enabled==true) | .name' <<< "$org")"

      if [[ -z "$ENABLED_REPOS" ]]; then
        echo "⚠️  Dashboard enabled but no repos enabled for $OWNER"
      fi
    done

echo
echo "✅ Infra registry validation PASSED"
