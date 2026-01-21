#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Task Assistant Infra Registry CLI
#
# Purpose
#   Operator-only registry mutation tool for sandbox onboarding.
#   Mutates infra/telemetry-registry.json deterministically.
#
# Commands
#   infra.sh register   <org>/<repo> [--telemetry-repo <org>/<repo>] [--reason <text>]
#   infra.sh disable    <org>/<repo> [--reason <text>]
#   infra.sh unregister <org>/<repo> --confirm-delete [--reason <text>]
#
# Constraints (Phase 3.4)
#   - Sandbox-only mutations. This tool will refuse production mutations.
#   - Registry schema is assumed to be validated by scripts/infra/validate-registry.sh in CI.
#   - This tool does NOT call GitHub APIs. It only edits the local registry file.
#
# Notes
#   - "process" and "context" are enforced for changelog compatibility.
#   - Telemetry repo is required on register unless already present in org config.
# ─────────────────────────────────────────────────────────────

REGISTRY_FILE="infra/telemetry-registry.v2.json"

die() { echo "infra: $*" >&2; exit 1; }

need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

usage() {
  cat >&2 <<'USAGE'
Usage:
  ./scripts/infra/infra.sh register   <org>/<repo> [--telemetry-repo <org>/<repo>] [--reason <text>]
  ./scripts/infra/infra.sh disable    <org>/<repo> [--reason <text>]
  ./scripts/infra/infra.sh unregister <org>/<repo> --confirm-delete [--reason <text>]

Examples:
  ./scripts/infra/infra.sh register automated-assistant-systems/task-assistant-sandbox --telemetry-repo automated-assistant-systems/task-assistant-telemetry --reason "Initial sandbox onboarding"
  ./scripts/infra/infra.sh disable automated-assistant-systems/task-assistant-sandbox --reason "Temporary pause"
  ./scripts/infra/infra.sh unregister automated-assistant-systems/task-assistant-sandbox --confirm-delete --reason "Sandbox retired"

Phase 3.4 Safety:
  - Sandbox-only mutations are allowed. Production mutations are refused.
USAGE
}

ensure_repo_root() {
  [[ -f "$REGISTRY_FILE" ]] || die "expected $REGISTRY_FILE at repo root; run from task-assistant-infra root"
}

parse_target() {
  local target="$1"
  [[ "$target" == */* ]] || die "target must be <org>/<repo>, got: $target"
  ORG="${target%%/*}"
  REPO="${target#*/}"
  [[ -n "$ORG" && -n "$REPO" ]] || die "invalid target: $target"
}

# Phase 3.4: sandbox-only rule.
# Conservative definition: repo name must contain "sandbox".
is_sandbox_target() {
  local repo="$1"
  [[ "$repo" == *sandbox* ]]
}

require_sandbox_target() {
  is_sandbox_target "$REPO" || die "refusing non-sandbox target in Phase 3.4: ${ORG}/${REPO}"
}

# Read org-level telemetry repo from registry, if present.
get_org_telemetry_repo() {
  jq -r --arg org "$ORG" '.orgs[$org].telemetry_repo // empty' "$REGISTRY_FILE"
}

# Does repo entry exist?
repo_exists() {
  jq -e --arg org "$ORG" --arg repo "$REPO" '.orgs[$org].repos[$repo] != null' "$REGISTRY_FILE" >/dev/null 2>&1
}

get_repo_state() {
  jq -r --arg org "$ORG" --arg repo "$REPO" '.orgs[$org].repos[$repo].state // "absent"' "$REGISTRY_FILE"
}

write_registry() {
  local tmp
  tmp="$(mktemp)"
  jq "$@" "$REGISTRY_FILE" > "$tmp"
  mv "$tmp" "$REGISTRY_FILE"
}

main() {
  need_cmd jq
  ensure_repo_root

  [[ $# -ge 2 ]] || { usage; exit 2; }

  local cmd="$1"; shift
  local target="$1"; shift
  parse_target "$target"
  require_sandbox_target

  local telemetry_repo=""
  local reason=""
  local confirm_delete="false"

  # parse flags
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --telemetry-repo)
        shift
        [[ $# -gt 0 ]] || die "--telemetry-repo requires a value"
        telemetry_repo="$1"
        ;;
      --reason)
        shift
        [[ $# -gt 0 ]] || die "--reason requires a value"
        reason="$1"
        ;;
      --confirm-delete)
        confirm_delete="true"
        ;;
      -h|--help)
        usage
        exit 0
        ;;
      *)
        die "unknown argument: $1"
        ;;
    esac
    shift
  done

  # Resolve telemetry repo
  local org_telemetry_repo
  org_telemetry_repo="$(get_org_telemetry_repo || true)"

  case "$cmd" in
    register)
      if repo_exists; then
        die "repo already registered: ${ORG}/${REPO} (state=$(get_repo_state))"
      fi

      # Telemetry repo must be known either via org config or flag
      if [[ -z "$org_telemetry_repo" && -z "$telemetry_repo" ]]; then
        die "telemetry repo not specified and org telemetry_repo missing; provide --telemetry-repo <org>/<repo> or set .orgs[org].telemetry_repo"
      fi

      # If flag provided, ensure it looks like org/repo
      if [[ -n "$telemetry_repo" && "$telemetry_repo" != */* ]]; then
        die "--telemetry-repo must be <org>/<repo>, got: $telemetry_repo"
      fi

      # Ensure org container exists; if not, create minimal org entry with telemetry_repo if provided.
      # Repo entry includes state + context/process for downstream audit semantics.
      write_registry '
        .orgs as $orgs
        | (if .orgs[$org] == null then .orgs[$org] = { telemetry_repo: ($telemetry_repo // null), repos: {} } else . end)
        | (if .orgs[$org].repos == null then .orgs[$org].repos = {} else . end)
        | (if (.orgs[$org].telemetry_repo == null or .orgs[$org].telemetry_repo == "") and ($telemetry_repo != null and $telemetry_repo != "") then
             .orgs[$org].telemetry_repo = $telemetry_repo
           else . end)
        | .orgs[$org].repos[$repo] = {
            "state": "enabled",
            "context": "sandbox",
            "process": "infra-cli",
            "reason": ($reason // "")
          }
      ' --arg org "$ORG" --arg repo "$REPO" --arg telemetry_repo "${telemetry_repo:-}" --arg reason "$reason"

      echo "infra: registered sandbox repo ${ORG}/${REPO}"
      ;;

    disable)
      repo_exists || die "repo not registered: ${ORG}/${REPO}"
      local prev
      prev="$(get_repo_state)"
      if [[ "$prev" == "disabled" ]]; then
        echo "infra: repo already disabled: ${ORG}/${REPO}"
        exit 0
      fi
      [[ "$prev" == "enabled" ]] || die "unexpected repo state '$prev' for ${ORG}/${REPO}"

      write_registry '
        .orgs[$org].repos[$repo].state = "disabled"
        | .orgs[$org].repos[$repo].process = "infra-cli"
        | .orgs[$org].repos[$repo].context = "sandbox"
        | (if ($reason != null) then .orgs[$org].repos[$repo].reason = $reason else . end)
      ' --arg org "$ORG" --arg repo "$REPO" --arg reason "$reason"

      echo "infra: disabled sandbox repo ${ORG}/${REPO}"
      ;;

    unregister)
      repo_exists || die "repo not registered: ${ORG}/${REPO}"
      [[ "$confirm_delete" == "true" ]] || die "refusing delete without --confirm-delete"

      write_registry '
        del(.orgs[$org].repos[$repo])
      ' --arg org "$ORG" --arg repo "$REPO"

      echo "infra: deleted sandbox repo ${ORG}/${REPO}"
      ;;

    *)
      usage
      die "unknown command: $cmd"
      ;;
  esac

  # Optional local validation (fast) if validate script exists
  if [[ -x "scripts/infra/validate-registry.v2.sh" ]]; then
    echo "infra: running local registry validation..."
    ./scripts/infra/validate-registry.v2.sh
  else
    echo "infra: NOTE: scripts/infra/validate-registry.v2.sh not executable; CI will validate"
  fi

  echo "infra: done"
}

main "$@"
