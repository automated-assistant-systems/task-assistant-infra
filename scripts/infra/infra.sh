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
CHANGELOG_FILE="infra/changelog/infra-changelog.jsonl"

die() { echo "infra: $*" >&2; exit 1; }
need_cmd() { command -v "$1" >/dev/null 2>&1 || die "missing required command: $1"; }

need_cmd jq
need_cmd git

usage() {
  cat >&2 <<'USAGE'
Usage:
  infra.sh register   --owner <org> --repo <repo> --telemetry <repo> --context <sandbox|production> [--reason <text>]
  infra.sh disable    --owner <org> --repo <repo> [--reason <text>]
  infra.sh unregister --owner <org> --repo <repo> --confirm-delete [--reason <text>]
USAGE
}

require_safe_git_state() {
  local branch
  branch="$(git rev-parse --abbrev-ref HEAD)"

  [[ "$branch" != "main" ]] || die "refusing to run on main"
  [[ -z "$(git status --porcelain)" ]] || die "working tree must be clean"
}

ensure_repo_root() {
  [[ -f "$REGISTRY_FILE" ]] || die "missing $REGISTRY_FILE"
  mkdir -p "$(dirname "$CHANGELOG_FILE")"
  [[ -f "$CHANGELOG_FILE" ]] || touch "$CHANGELOG_FILE"
}

append_changelog() {
  local action="$1"
  local ts
  ts="$(date -u +"%Y-%m-%dT%H:%M:%SZ")"

  jq -c -n \
    --arg timestamp "$ts" \
    --arg action "$action" \
    --arg owner "$OWNER" \
    --arg repo "$REPO" \
    --arg context "${CONTEXT:-}" \
    --arg telemetry "$TELEMETRY" \
    --arg reason "${REASON:-}" \
    '{
      timestamp: $timestamp,
      action: $action,
      owner: $owner,
      repo: $repo,
      context: ($context | select(length > 0)),
      telemetry_repo: ($telemetry | select(length > 0)),
      reason: ($reason | select(length > 0)),
      process: "infra-cli",
      schema_version: "2.0"
    }' >> "$CHANGELOG_FILE"
}

write_registry() {
  jq -e '.schema_version | startswith("2.")' "$REGISTRY_FILE" \
    || die "registry schema_version missing"

  local tmp
  tmp="$(mktemp)"
  jq "$@" "$REGISTRY_FILE" > "$tmp"
  mv "$tmp" "$REGISTRY_FILE"
}

repo_exists() {
  jq -e --arg o "$OWNER" --arg r "$REPO" \
    '.orgs[$o].repos[$r] != null' "$REGISTRY_FILE" >/dev/null
}

# ─────────────────────────────────────────────

main() {
  require_safe_git_state
  ensure_repo_root

  [[ $# -ge 1 ]] || usage

  ACTION="$1"
  shift
  readonly ACTION

  OWNER=""
  REPO=""
  TELEMETRY=""
  CONTEXT=""
  REASON=""
  CONFIRM_DELETE="false"

  while [[ $# -gt 0 ]]; do
    case "$1" in
      --owner) shift; OWNER="$1" ;;
      --repo) shift; REPO="$1" ;;
      --telemetry) shift; TELEMETRY="$1" ;;
      --context) shift; CONTEXT="$1" ;;
      --reason) shift; REASON="$1" ;;
      --confirm-delete) CONFIRM_DELETE="true" ;;
      *) die "unknown argument: $1" ;;
    esac
    shift
  done

  [[ -n "$OWNER" && -n "$REPO" ]] || die "--owner and --repo required"

  case "$ACTION" in
    register)
      [[ -n "$TELEMETRY" && -n "$CONTEXT" ]] || die "register requires --telemetry and --context"

      repo_exists && die "repo already registered"

      write_registry '
        .orgs = (.orgs // {})
        | .orgs[$o] = (.orgs[$o] // { telemetry_repo: ($o + "/" + $t), repos: {} })
        | .orgs[$o].repos[$r] = {
            state: "enabled",
            context: $c,
            process: "infra-cli",
            reason: ($reason // "")
          }
      ' --arg o "$OWNER" --arg r "$REPO" --arg t "$TELEMETRY" --arg c "$CONTEXT" --arg reason "$REASON"

      append_changelog "register"
      ;;

    disable)
      repo_exists || die "repo not registered"

      write_registry '
        .orgs[$o].repos[$r].state = "disabled"
        | .orgs[$o].repos[$r].process = "infra-cli"
        | .orgs[$o].repos[$r].reason = ($reason // "")
      ' --arg o "$OWNER" --arg r "$REPO" --arg reason "$REASON"

      append_changelog "disable"
      ;;

    unregister)
      repo_exists || die "repo not registered"
      [[ "$CONFIRM_DELETE" == "true" ]] || die "use --confirm-delete"

      write_registry 'del(.orgs[$o].repos[$r])' \
        --arg o "$OWNER" --arg r "$REPO"

      append_changelog "unregister"
      ;;

    *)
      die "unknown action: $ACTION"
      ;;
  esac

  [[ -x scripts/infra/validate-registry-v2.sh ]] && scripts/infra/validate-registry-v2.sh

  echo "infra: $ACTION completed for $OWNER/$REPO"
}

main "$@"
