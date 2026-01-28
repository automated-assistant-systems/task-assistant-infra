#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Task Assistant Infra Registry CLI (v2-only)
#
# Purpose
#   Operator-only registry mutation tool.
#   Mutates infra/telemetry-registry.v2.json deterministically.
#
# Commands
#   infra.sh register   <org>/<repo> --context <sandbox|production> \
#                       [--telemetry-repo <org>/<repo>] [--reason <text>]
#
#   infra.sh disable    <org>/<repo> [--reason <text>]
#
#   infra.sh unregister <org>/<repo> --confirm-delete [--reason <text>]
#
# Safety
#   - Explicit --context required on register
#   - Destructive actions require confirmation
#   - No GitHub API calls (local registry only)
#
# Notes
#   - infra v1 is deprecated; this tool is v2-only
#   - Telemetry resolution is authoritative via v2
# ─────────────────────────────────────────────────────────────

REGISTRY_FILE="infra/telemetry-registry.v2.json"

die() { echo "infra: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

usage() {
  cat >&2 <<'USAGE'
Usage:
  ./scripts/infra/infra.sh register <org>/<repo> \
      --context <sandbox|production> \
      [--telemetry-repo <org>/<repo>] \
      [--reason <text>]

  ./scripts/infra/infra.sh disable <org>/<repo> [--reason <text>]

  ./scripts/infra/infra.sh unregister <org>/<repo> --confirm-delete [--reason <text>]

Examples:
  ./scripts/infra/infra.sh register automated-assistant-systems/task-assistant \
      --context production \
      --telemetry-repo automated-assistant-systems/task-assistant-telemetry \
      --reason "Marketplace production repo"

  ./scripts/infra/infra.sh register garybayes/ta-marketplace-install-test \
      --context sandbox \
      --reason "Marketplace sandbox test"

Notes:
  - infra v2 only
  - context is explicit; no name-based inference
USAGE
}

ensure_repo_root() {
  [[ -f "$REGISTRY_FILE" ]] || die "expected $REGISTRY_FILE at repo root"
}

parse_target() {
  local target="$1"
  [[ "$target" == */* ]] || die "target must be <org>/<repo>"
  ORG="${target%%/*}"
  REPO="${target#*/}"
}

repo_exists() {
  jq -e --arg org "$ORG" --arg repo "$REPO" \
    '.orgs[$org].repos[$repo] != null' "$REGISTRY_FILE" >/dev/null 2>&1
}

get_repo_state() {
  jq -r --arg org "$ORG" --arg repo "$REPO" \
    '.orgs[$org].repos[$repo].state // "absent"' "$REGISTRY_FILE"
}

get_org_telemetry_repo() {
  jq -r --arg org "$ORG" '.orgs[$org].telemetry_repo // empty' "$REGISTRY_FILE"
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

  local telemetry_repo=""
  local reason=""
  local context=""
  local confirm_delete="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --telemetry-repo) shift; telemetry_repo="${1:-}";;
      --context)        shift; context="${1:-}";;
      --reason)         shift; reason="${1:-}";;
      --confirm-delete) confirm_delete="true";;
      -h|--help) usage; exit 0;;
      *) die "unknown argument: $1";;
    esac
    shift
  done

  case "$cmd" in
    register)
      [[ -n "$context" ]] || die "--context is required (sandbox|production)"
      [[ "$context" == "sandbox" || "$context" == "production" ]] \
        || die "invalid context: $context"

      repo_exists && die "repo already registered: ${ORG}/${REPO}"

      local org_telemetry
      org_telemetry="$(get_org_telemetry_repo || true)"

      if [[ -z "$org_telemetry" && -z "$telemetry_repo" ]]; then
        die "telemetry repo not specified and org telemetry_repo missing"
      fi

      write_registry '
        .orgs as $orgs
        | (if .orgs[$org] == null
            then .orgs[$org] = { telemetry_repo: ($telemetry_repo // null), repos: {} }
            else . end)
        | (if .orgs[$org].repos == null then .orgs[$org].repos = {} else . end)
        | (if (.orgs[$org].telemetry_repo == null or .orgs[$org].telemetry_repo == "")
             and ($telemetry_repo != null and $telemetry_repo != "")
           then .orgs[$org].telemetry_repo = $telemetry_repo
           else . end)
        | .orgs[$org].repos[$repo] = {
            state: "enabled",
            context: $context,
            process: "infra-cli",
            reason: ($reason // "")
          }
      ' \
        --arg org "$ORG" \
        --arg repo "$REPO" \
        --arg telemetry_repo "${telemetry_repo:-}" \
        --arg context "$context" \
        --arg reason "$reason"

      echo "infra: registered ${context} repo ${ORG}/${REPO}"
      ;;

    disable)
      repo_exists || die "repo not registered: ${ORG}/${REPO}"
      [[ "$(get_repo_state)" == "enabled" ]] || die "repo not enabled"

      write_registry '
        .orgs[$org].repos[$repo].state = "disabled"
        | .orgs[$org].repos[$repo].process = "infra-cli"
        | (if ($reason != null) then .orgs[$org].repos[$repo].reason = $reason else . end)
      ' --arg org "$ORG" --arg repo "$REPO" --arg reason "$reason"

      echo "infra: disabled repo ${ORG}/${REPO}"
      ;;

    unregister)
      repo_exists || die "repo not registered: ${ORG}/${REPO}"
      [[ "$confirm_delete" == "true" ]] || die "missing --confirm-delete"

      write_registry 'del(.orgs[$org].repos[$repo])' \
        --arg org "$ORG" --arg repo "$REPO"

      echo "infra: unregistered repo ${ORG}/${REPO}"
      ;;

    *)
      usage
      die "unknown command: $cmd"
      ;;
  esac

  if [[ -x scripts/infra/validate-registry-v2.sh ]]; then
    echo "infra: validating registry..."
    scripts/infra/validate-registry-v2.sh
  fi

  echo "infra: done"
}

main "$@"
