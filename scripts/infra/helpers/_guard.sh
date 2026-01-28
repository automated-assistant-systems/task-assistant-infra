# scripts/infra/helpers/_guard.sh
REPO="$(gh repo view --json name -q .name)"
[[ "$REPO" == "task-assistant-infra" ]] \
  || { echo "infra-only helper"; exit 1; }

BRANCH="$(git branch --show-current)"
[[ "$BRANCH" != "main" ]] \
  || { echo "refusing to run on main"; exit 1; }

git diff --quiet || { echo "working tree dirty"; exit 1; }
