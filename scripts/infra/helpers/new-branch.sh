#!/usr/bin/env bash
set -euo pipefail

source "$(dirname "$0")/_guard.sh"

name="${1:-}"

if [[ -z "$name" ]]; then
  echo "Usage: new-branch.sh <branch-name>"
  exit 1
fi

git checkout main
git pull --ff-only
git checkout -b "infra/$name"

echo "✓ Switched to infra/$name"
