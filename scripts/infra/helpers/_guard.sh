#!/usr/bin/env bash
set -euo pipefail

current_branch="$(git branch --show-current)"

[[ -n "$current_branch" ]] || {
  echo "❌ detached HEAD; checkout a branch first" >&2
  exit 1
}

if [[ "$current_branch" == "main" ]]; then
  echo "❌ refusing to mutate infra registry on main" >&2
  echo "   create a branch first" >&2
  exit 1
fi

git diff --quiet || {
  echo "❌ working tree not clean" >&2
  exit 1
}

git diff --cached --quiet || {
  echo "❌ index not clean" >&2
  exit 1
}
