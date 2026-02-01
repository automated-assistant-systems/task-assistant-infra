# Task Assistant Infra Registry (v2)

## Purpose

The infra registry defines the **authoritative relationship** between:

- repositories  
- their execution context (`sandbox` vs `production`)  
- their telemetry destination  

This registry exists to ensure:

- deterministic telemetry routing  
- strict separation between sandbox and production  
- prevention of cross-organization telemetry writes  
- reproducible validation and enforcement behavior  

**Infra v2 is the single source of truth.**  
Infra v1 is deprecated and no longer used for resolution.

---

## What This Repository Controls

This repository **does not run engines or workflows**.

It controls:

- which repositories are considered active  
- whether a repository is sandbox or production  
- which telemetry repository each org writes to  
- whether a repo is enabled or disabled  
- how engines resolve infra context during execution  

All engines, validation scripts, and dashboards consume infra data **indirectly**.

---

## Registry File

**Path**

infra/telemetry-registry.v2.json

yaml
Copy code

---

## Responsibilities

The registry:

- defines org-level telemetry routing  
- defines repo-level execution context  
- blocks cross-org telemetry writes  
- provides immutable audit metadata (`process`, `reason`)  

This file is **manually mutated via controlled scripts only**.

---

## Registry Structure (Conceptual)

```json
{
  "orgs": {
    "<org>": {
      "telemetry_repo": "<org>/<telemetry-repo>",
      "repos": {
        "<repo>": {
          "state": "enabled | disabled",
          "context": "sandbox | production",
          "process": "infra-cli",
          "reason": "operator-supplied text"
        }
      }
    }
  }
}
Key Rules
Telemetry repositories are per org

A repo may not write telemetry to another org

Context is explicit — never inferred from naming

All registry mutations are intentional and auditable

Infra v2 Rules (Non-Negotiable)
1. Explicit Context
Every registered repo must declare:

diff
Copy code
--context sandbox | production
No name-based inference is allowed.

2. Telemetry Ownership Enforcement
A repository:

php-template
Copy code
<owner>/<repo>
may only write telemetry to:

php-template
Copy code
<owner>/<telemetry-repo>
Cross-org telemetry writes are forbidden.

3. Registry Mutations Require a Branch
No registry edits on main

All changes go through PRs

All changes are validated before merge

4. Infra Is Operator-Only
infra.sh does not call GitHub APIs

It mutates local files only

CI validates schema correctness

GitHub enforces review and merge rules

Primary Scripts
scripts/infra/infra.sh
Purpose

Authoritative CLI for mutating the infra registry.

Supported Commands

bash
Copy code
infra.sh register <org>/<repo> \
  --context <sandbox|production> \
  [--telemetry-repo <org>/<repo>] \
  [--reason <text>]

infra.sh disable <org>/<repo> [--reason <text>]

infra.sh unregister <org>/<repo> \
  --confirm-delete \
  [--reason <text>]
What It Enforces

explicit context

telemetry ownership

registry schema correctness

no implicit defaults

scripts/infra/helpers/new-branch.sh
Creates a correctly named feature branch.

Rules

must be run from main

refuses if working tree is dirty

standardizes branch creation

scripts/infra/helpers/finalize-registry.sh
Required before committing registry changes.

What It Does

refuses to run on main

verifies registry was modified

validates v2 schema

enforces telemetry ownership

stages registry file

confirms clean working tree

This script prevents accidental or incomplete infra changes.

scripts/infra/helpers/create-pr.sh
Creates a PR from the current branch.

Refuses if

on main

working tree is dirty

no commits exist

branch is not pushed

scripts/infra/helpers/merge-pr.sh
Safely merges a PR via gh.

accepts PR number, or

auto-detects PR for current branch

uses squash + delete branch

Standard Infra Workflow
Registering a Repository
bash
Copy code
scripts/infra/helpers/new-branch.sh infra/register-example

scripts/infra/infra.sh register <org>/<repo> \
  --context sandbox \
  --telemetry-repo <org>/<telemetry-repo> \
  --reason "Why this repo exists"

scripts/infra/helpers/finalize-registry.sh

git commit -m "infra: register <org>/<repo>"
git push -u origin infra/register-example

scripts/infra/helpers/create-pr.sh
scripts/infra/helpers/merge-pr.sh
Sandbox vs Production
Aspect	Sandbox	Production
Purpose	Testing / validation	Marketplace / live use
Telemetry	Required	Required
Enforcement	Full	Full
Safety	Resettable	Immutable

Sandbox does not mean “less strict.”
It means explicitly non-production.

Why Infra v1 Was Deprecated
Infra v1 relied on:

repo name inference

implicit sandbox detection

mixed responsibilities

Infra v2 exists to:

remove ambiguity

prevent accidental production impact

support deterministic validation

scale beyond Phase 3.4

Operator Responsibilities
If you touch infra:

you are changing system behavior

you must document intent (reason)

you must use the helpers

you must review diffs carefully

Infra mistakes are silent but catastrophic.
The process is strict by design.

Final Principle
If infra is wrong, everything downstream lies.

This repository exists to make infra boring, explicit, and correct.
