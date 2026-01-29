OPERATOR_PLAYBOOK.md

Repository: task-assistant-infra
Audience: Human operators only
Scope: Infra v2 registry mutations (authoritative)

This playbook defines the only supported flows for modifying infrastructure state.

If it’s not here, don’t do it.

Core Rules (Read Once)

❌ Never work directly on main

❌ Never bypass helpers

❌ Never mix registry changes with other edits

✅ One change → one branch → one PR

✅ Registry is authoritative; engines obey it blindly

Flow 1 — Register a Sandbox Repo (Most Common)
Example

Register garybayes/ta-marketplace-install-test as a sandbox repo with garybayes telemetry.

Steps
# 1. Create a branch
scripts/infra/helpers/new-branch.sh infra/register-garybayes-sandbox

# 2. Register repo
scripts/infra/infra.sh register garybayes/ta-marketplace-install-test \
  --context sandbox \
  --telemetry-repo garybayes/task-assistant-telemetry \
  --reason "Marketplace install sandbox for Phase 3.4 validation"

# 3. Finalize registry (hard gate)
scripts/infra/helpers/finalize-registry.sh

# 4. Create PR
scripts/infra/helpers/create-pr.sh

# 5. Merge PR (after approval)
scripts/infra/helpers/merge-pr.sh

Flow 2 — Register a Production Repo

⚠️ Production registration is rare and intentional

Example

Register automated-assistant-systems/task-assistant as production.

scripts/infra/helpers/new-branch.sh infra/register-task-assistant-prod

scripts/infra/infra.sh register automated-assistant-systems/task-assistant \
  --context production \
  --telemetry-repo automated-assistant-systems/task-assistant-telemetry \
  --reason "Primary Task Assistant production repo"

scripts/infra/helpers/finalize-registry.sh
scripts/infra/helpers/create-pr.sh
scripts/infra/helpers/merge-pr.sh

Flow 3 — Disable a Repo (Non-Destructive)

Used to pause telemetry ingestion without deleting history.

scripts/infra/helpers/new-branch.sh infra/disable-repo

scripts/infra/infra.sh disable garybayes/ta-marketplace-install-test \
  --reason "Sandbox retired after Phase 3.4"

scripts/infra/helpers/finalize-registry.sh
scripts/infra/helpers/create-pr.sh
scripts/infra/helpers/merge-pr.sh

Flow 4 — Unregister a Repo (Rare)

⚠️ Deletes the repo entry from v2 registry

scripts/infra/helpers/new-branch.sh infra/unregister-repo

scripts/infra/infra.sh unregister garybayes/ta-marketplace-install-test \
  --confirm-delete \
  --reason "Sandbox no longer required"

scripts/infra/helpers/finalize-registry.sh
scripts/infra/helpers/create-pr.sh
scripts/infra/helpers/merge-pr.sh

Safety Checklist (Before Creating PR)

If any answer is “no”, stop.

 On a feature branch (not main)

 Only infra/telemetry-registry.v2.json changed

 Context explicitly set (sandbox or production)

 Telemetry repo owner matches repo owner

 finalize-registry.sh passes cleanly

What NOT To Do (Ever)

❌ Edit registry and helpers in same PR

❌ Register repos without telemetry

❌ Share telemetry across orgs

❌ Infer context from repo names

❌ Fix infra mistakes in engines

Infra mistakes are fixed here or nowhere.

Mental Model (Remember This)

Infra is law.
Engines are dumb.
Operators are accountable.

If something breaks downstream and infra allowed it — infra was wrong.
