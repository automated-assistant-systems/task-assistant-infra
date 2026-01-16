Task Assistant — Infrastructure Repository

Repository: task-assistant-infra
System: Task Assistant (GitHub Marketplace App)
Purpose: Centralized infrastructure state for Task Assistant runtime engines
Status: Authoritative / Locked

1. Purpose

This repository contains infrastructure-level configuration and registries used by Task Assistant runtime engines.

It is not a product repository, not a customer repository, and not an execution environment.

Its sole responsibility is to provide deterministic, auditable inputs to system-level engines (e.g. dashboards, aggregation, future SaaS services).

2. What Lives Here (Authoritative)

This repository currently contains:

telemetry-registry.json


This file is the single source of truth for:

Which GitHub organizations participate in Task Assistant telemetry

Which telemetry repositories should be scanned

Which telemetry sources are active vs inactive

3. What Does NOT Live Here

The following must never live in this repository:

❌ Runtime code
❌ GitHub Actions workflows
❌ Telemetry data
❌ Customer configuration
❌ Secrets
❌ Product logic
❌ SaaS backend code

This repository is read-only input to engines.

4. Telemetry Registry (Authoritative)
File
telemetry-registry.json

Responsibility

The registry declares explicitly and exhaustively which telemetry repositories exist.

The system does not:

Discover repos dynamically

Scan organizations heuristically

Infer participation

Query GitHub to “find” telemetry

If a telemetry repo is not listed here, it does not exist to the system.

Schema Versioning
{
  "schema_version": "1.0"
}


Rules:

Major version changes are breaking

Minor versions must be backward compatible

Engines must refuse unsupported major versions

Registry Entry Semantics

Each entry represents one organization-scoped telemetry repository.

Example:

{
  "org": "automated-assistant-systems",
  "repo": "task-assistant-telemetry",
  "visibility": "public",
  "status": "active",
  "added_at": "2026-01-10T14:22:00Z",
  "added_by": "system",
  "notes": "Primary production org"
}

Field meanings
Field	Meaning
org	GitHub organization name
repo	Telemetry repository name
visibility	Informational only (public / private)
status	active or inactive
added_at	Audit timestamp
added_by	system or manual
notes	Human context (ignored by engines)
Engine Consumption Rules (Non-Negotiable)

Engines consuming this registry must:

Ignore unknown fields

Ignore entries with status != "active"

Treat this registry as authoritative

Never mutate this repository

Never infer missing data

5. How This Repository Is Used
Current Consumers

Dashboard Engine

Scans all active telemetry repos

Builds aggregated dashboards

Runs on a scheduled cadence (daily)

Future Consumers (Planned)

SaaS backend ingestion

Cross-org analytics

Marketplace diagnostics

Compliance & audit tooling

6. Update Policy
How changes are made

Changes are made only via Pull Request

No automated writes

No runtime mutation

When to update the registry

Add a new entry when:

A new organization installs Task Assistant

A telemetry repository is created for that org

Update an entry when:

Telemetry repo is deprecated

Org participation is paused

Never delete entries — use status: inactive.

7. Permissions & Security

This repository is read-only for runtime engines

No secrets are stored here

No credentials are required to consume it

Public visibility is acceptable and intentional

This design ensures:

Marketplace safety

Auditability

Deterministic behavior

Zero risk of data mutation

8. Architectural Rationale

This repository exists to enforce separation of concerns:

Concern	Location
Product logic	task-assistant
Runtime execution	GitHub Actions engines
Customer data	Telemetry repos (per org)
Infrastructure state	This repository

Registries are infrastructure — not features.

9. Non-Goals

This repository will never:

Execute workflows

Store telemetry

Replace customer configuration

Act as a SaaS backend

10. Status

This repository is authoritative.

Any runtime behavior not justified by data in this repository is a defect.

Any engine that ignores this registry is invalid.
