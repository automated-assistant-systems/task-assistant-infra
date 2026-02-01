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

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"$SCRIPT_DIR/helpers/_guard.sh"

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

require_safe_git_state() {
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)"

  if [[ "$branch" == "main" ]]; then
    echo "infra: refusing to run on branch 'main'"
    echo
    echo "Create or switch to a feature branch first:"
    echo "  git checkout -b infra/<change-name>"
    exit 1
  fi

  if [[ -n "$(git status --porcelain)" ]]; then
    echo "infra: working tree is dirty"
    echo "Commit or stash changes before running infra mutations."
    exit 1
  fi
}

ensure_repo_root() {
  [[ -f "$REGISTRY_FILE" ]] || die "expected $REGISTRY_FILE at repo root"
}

write_registry() {
  jq -e '.schema_version | startswith("2.")' "$REGISTRY_FILE" \
    || die "registry corruption detected: schema_version missing"
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
  require_safe_git_state

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
        . as $root
        | .orgs = (
            .orgs // {}
            | (if .[$o] == null then
                 .[$o] = { telemetry_repo: ($o + "/" + $t), repos: {} }
               else
                 .
               end)
            | (if .[$o].telemetry_repo == null then
                 .[$o].telemetry_repo = ($o + "/" + $t)
               else
                 .
               end)
            | .[$o].repos[$r] = {
                "state": "enabled",
                "context": $c,
                "process": "infra-cli",
                "reason": ($reason // "")
              }
          )
      '

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
