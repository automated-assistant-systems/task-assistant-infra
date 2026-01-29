🚧 Task Assistant — Infra Rules (v2)

Infra defines reality.
If infra is wrong, everything downstream lies.

This document is the non-negotiable contract for operating the Task Assistant infra registry.

1️⃣ Infra v2 Is the Source of Truth

infra/telemetry-registry.v2.json is authoritative

Infra v1 is deprecated

No name-based inference

No implicit defaults

If it’s not in infra v2, it doesn’t exist.

2️⃣ Explicit Context Is Mandatory

Every registered repo must declare:

context = sandbox | production


Context is never inferred

Sandbox ≠ relaxed rules

Production ≠ mutable

3️⃣ Telemetry Is Per-Org (No Exceptions)

A repo:

<owner>/<repo>


may only write telemetry to:

<owner>/<telemetry-repo>


🚫 Cross-org telemetry is forbidden
🚫 Shared telemetry across orgs is forbidden

This prevents:

data leakage

privilege escalation

false validation results

4️⃣ Registry Mutations Require a Branch + PR

You may not edit infra on main.

Required flow:

new branch
→ infra.sh mutation
→ finalize-registry.sh
→ commit
→ PR
→ merge


If it bypasses PR review, it’s invalid.

5️⃣ infra.sh Is the Only Mutation Interface

Allowed operations:

register

disable

unregister

infra.sh:

edits local registry only

enforces schema rules

records operator intent (reason)

does not call GitHub APIs

Manual edits are prohibited.

6️⃣ Helpers Are Part of the Contract

Required helpers:

new-branch.sh

finalize-registry.sh

create-pr.sh

merge-pr.sh

They exist to:

prevent mistakes

enforce sequencing

eliminate “oops” commits

If you skip helpers, you’re skipping safety.

7️⃣ Sandbox ≠ Disposable Infra

Sandbox repos:

are fully enforced

emit real telemetry

must be explicitly registered

must be explicitly reset

The only difference from production is intent, not behavior.

8️⃣ Infra Changes Are System Changes

If you touch infra, you are changing:

telemetry routing

enforcement behavior

validation truth

dashboard accuracy

This is not configuration.
This is system state.

9️⃣ Auditability Is Required

Every registration must include:

process (who/what made the change)

reason (why it exists)

If you can’t explain it later, it shouldn’t exist now.

🔟 Final Rule (Read This Twice)

If you don’t have time to do infra correctly,
you will absolutely have time to debug it later.

Infra exists so that:

validation is trustworthy

sandboxes are safe

production is protected

operators can sleep

✅ Infra v2 Goal

Make infra boring, explicit, and impossible to misuse.
