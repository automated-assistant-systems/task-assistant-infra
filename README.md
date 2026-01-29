Task Assistant — Infrastructure Repository

Repository: task-assistant-infra
System: Task Assistant (GitHub Marketplace App)
Role: Infrastructure registry & enforcement backbone
Status: Authoritative / Locked

1. Purpose

This repository defines infrastructure state for the Task Assistant system.

It is not:

a product repository

a customer repository

a runtime or execution environment

Its sole responsibility is to provide deterministic, auditable, operator-controlled inputs to Task Assistant engines.

If infrastructure data is wrong, all downstream behavior is invalid.

2. Infra v2: Source of Truth

This repository operates under Infra v2.

Infra v2 is:

explicit

schema-driven

org-scoped

PR-gated

non-inferential

Infra v1 is deprecated and no longer authoritative.

3. What Lives Here (Authoritative)
Primary Assets

infra/telemetry-registry.v2.json
The single source of truth for:

which orgs participate

which repos are production vs sandbox

where telemetry is written

whether a repo is enabled or disabled

Operator Tooling

scripts/infra/infra.sh — the only supported mutation interface

scripts/infra/helpers/ — guardrails and workflow helpers:

new-branch.sh

finalize-registry.sh

create-pr.sh

merge-pr.sh

4. What Does Not Live Here

This repository must never contain:

❌ Runtime code
❌ GitHub Actions workflows
❌ Telemetry data
❌ Customer configuration
❌ Secrets or credentials
❌ Product or SaaS logic

This repo is read-only input to engines.

5. Telemetry Registry (v2)
File
infra/telemetry-registry.v2.json

What It Defines

The registry declares explicitly and exhaustively:

participating GitHub orgs

per-org telemetry repositories

registered repos and their context

enabled vs disabled state

The system does not:

discover repos dynamically

infer sandbox vs production

scan orgs heuristically

“guess” telemetry locations

If it’s not in the registry, it does not exist.

6. Core Enforcement Rules (Non-Negotiable)
Explicit Context Required

Every repo must declare:

context = sandbox | production


No name-based inference. No defaults.

Telemetry Is Per-Org

A repo:

<owner>/<repo>


may only write telemetry to:

<owner>/<telemetry-repo>


🚫 Cross-org telemetry is forbidden
🚫 Shared telemetry across orgs is forbidden

This prevents data leakage, privilege escalation, and invalid validation.

Registry Mutations Are PR-Only

All infra changes must follow:

new branch
→ infra.sh mutation
→ finalize-registry.sh
→ commit
→ PR
→ merge


Direct writes to main are blocked by policy.

7. infra.sh — The Only Mutation Interface

infra.sh is the exclusive way to change infra state.

Supported operations:

register

disable

unregister

Characteristics:

local registry mutation only

no GitHub API calls

explicit operator intent (reason)

enforced schema validation

Manual edits to the registry are prohibited.

8. Helper Scripts (Required Workflow)

Helper scripts exist to prevent operator error:

new-branch.sh
Ensures mutations never happen on main

finalize-registry.sh
Validates schema and stages registry changes

create-pr.sh
Creates PR only from clean feature branches

merge-pr.sh
Merges safely and deletes branches

Skipping helpers means skipping safety.

9. Sandbox ≠ Reduced Enforcement

Sandbox repos:

are fully enforced

emit real telemetry

must be explicitly registered

must be explicitly reset

Sandbox differs from production only by intent, not behavior.

10. Audit & Traceability

Every registry entry records:

process — what performed the mutation

reason — why it exists

If it cannot be explained later, it should not exist now.

11. How Infra Is Consumed
Current Consumers

Dashboard Engine

scans active telemetry repos

aggregates diagnostics and dashboards

Planned Consumers

SaaS ingestion

Marketplace diagnostics

Compliance and audit tooling

Cross-org analytics

Engines must:

treat infra as authoritative

refuse unsupported schema versions

never mutate this repo

12. Architectural Rationale
Concern	Location
Product logic	task-assistant
Runtime execution	GitHub Actions engines
Customer data	Telemetry repos (per org)
Infrastructure state	This repository

Infrastructure is not a feature.
It is a system contract.

13. Final Word

If you don’t have time to do infra correctly,
you will absolutely have time to debug it later.

This repository exists so that:

validation is trustworthy

sandboxes are safe

production is protected

operators don’t guess

Any runtime behavior not justified by infra is a defect.
Any engine that ignores infra is invalid.
