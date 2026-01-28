#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────────────────────
# Task Assistant Infra Registry CLI (v2)
#
# Explicit, invariant-driven registry mutation tool.
#
# Invariants enforced:
#   • telemetry.owner === target.owner
#   • telemetry is repo-name only (no cross-org allowed)
#
# Commands
#   infra.sh register   --owner <org> --repo <repo> --telemetry <repo> --context <sandbox|production> [--reason <text>]
#   infra.sh disable    --owner <org> --repo <repo> [--reason <text>]
#   infra.sh unregister --owner <org> --repo <repo> --confirm-delete [--reason <text>]
#
# Registry
#   infra/telemetry-registry.v2.json
# ─────────────────────────────────────────────────────────────

REGISTRY_FILE="infra/telemetry-registry.v2.json"

die() { echo "infra: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

usage() {
  cat >&2 <<'USAGE'
Usage:
  ./scripts/infra/infra.sh register \
    --owner <org> \
    --repo <repo> \
    --telemetry <telemetry-repo-name> \
    --context <sandbox|production> \
    [--reason <text>]

  ./scripts/infra/infra.sh disable \
    --owner <org> \
    --repo <repo> \
    [--reason <text>]

  ./scripts/infra/infra.sh unregister \
    --owner <org> \
    --repo <repo> \
    --confirm-delete \
    [--reason <text>]

Notes:
  • --telemetry is repo-name ONLY (owner is derived)
  • Cross-org telemetry is not supported by design
  • Registry is validated locally if validation script exists
USAGE
}

ensure_repo_root() {
  [[ -f "$REGISTRY_FILE" ]] || die "expected $REGISTRY_FILE at repo root"
}

write_registry() {
  local tmp
  tmp="$(mktemp)"
  jq "$@" "$REGISTRY_FILE" > "$tmp"
  mv "$tmp" "$REGISTRY_FILE"
}

repo_exists() {
  jq -e --arg o "$OWNER" --arg r "$REPO" \
    '.orgs[$o].repos[$r] != null' "$REGISTRY_FILE" >/dev/null 2>&1
}

get_repo_state() {
  jq -r --arg o "$OWNER" --arg r "$REPO" \
    '.orgs[$o].repos[$r].state // "absent"' "$REGISTRY_FILE"
}

main() {
  need_cmd jq
  ensure_repo_root

  [[ $# -ge 1 ]] || { usage; exit 2; }

  CMD="$1"; shift

  OWNER=""
  REPO=""
  TELEMETRY=""
  CONTEXT=""
  REASON=""
  CONFIRM_DELETE="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --owner) shift; OWNER="${1:-}";;
      --repo) shift; REPO="${1:-}";;
      --telemetry) shift; TELEMETRY="${1:-}";;
      --context) shift; CONTEXT="${1:-}";;
      --reason) shift; REASON="${1:-}";;
      --confirm-delete) CONFIRM_DELETE="true";;
      -h|--help) usage; exit 0;;
      *) die "unknown argument: $1";;
    esac
    shift
  done

  [[ -n "$OWNER" ]] || die "--owner is required"
  [[ -n "$REPO" ]] || die "--repo is required"

  case "$CMD" in
    register)
      [[ -n "$TELEMETRY" ]] || die "--telemetry is required"
      [[ -n "$CONTEXT" ]] || die "--context is required"

      [[ "$TELEMETRY" != */* ]] || \
        die "--telemetry must be repo-name only (owner is derived)"

      [[ "$CONTEXT" == "sandbox" || "$CONTEXT" == "production" ]] || \
        die "--context must be sandbox or production"

      repo_exists && die "repo already registered: $OWNER/$REPO"

      write_registry '
        .orgs as $orgs
        | (if .orgs[$o] == null then
             .orgs[$o] = { telemetry_repo: $t, repos: {} }
           else
             .orgs[$o]
           end)
        | (if .orgs[$o].telemetry_repo == null then
             .orgs[$o].telemetry_repo = $t
           else
             .
           end)
        | .orgs[$o].repos[$r] = {
            "state": "enabled",
            "context": $c,
            "process": "infra-cli",
            "reason": ($reason // "")
          }
      ' \
        --arg o "$OWNER" \
        --arg r "$REPO" \
        --arg t "$TELEMETRY" \
        --arg c "$CONTEXT" \
        --arg reason "$REASON"

      echo "infra: registered $CONTEXT repo $OWNER/$REPO"
      ;;

    disable)
      repo_exists || die "repo not registered: $OWNER/$REPO"

      write_registry '
        .orgs[$o].repos[$r].state = "disabled"
        | .orgs[$o].repos[$r].process = "infra-cli"
        | (if $reason != null then .orgs[$o].repos[$r].reason = $reason else . end)
      ' --arg o "$OWNER" --arg r "$REPO" --arg reason "$REASON"

      echo "infra: disabled repo $OWNER/$REPO"
      ;;

    unregister)
      repo_exists || die "repo not registered: $OWNER/$REPO"
      [[ "$CONFIRM_DELETE" == "true" ]] || die "use --confirm-delete to unregister"

      write_registry 'del(.orgs[$o].repos[$r])' \
        --arg o "$OWNER" --arg r "$REPO"

      echo "infra: unregistered repo $OWNER/$REPO"
      ;;

    *)
      usage
      die "unknown command: $CMD"
      ;;
  esac

  if [[ -x "scripts/infra/validate-registry-v2.sh" ]]; then
    echo "infra: validating registry..."
    ./scripts/infra/validate-registry-v2.sh
  fi

  echo "infra: done"
}

main "$@"
