# Phase 0 — Scaffold and the tenancy package

Read these first: `docs/LLD.md`, `reference/schema.sql`

Set up the repository skeleton for this platform, then build the tenancy package.

Repository layout, per the LLD:
  apps/web/              Next.js console and customer portal
  services/api/          FastAPI application
  services/domain/       Domain services, modular monolith
  connectors/            One package per source system
  execution/             Credential broker and workers — EMPTY for now, do not implement
  packages/tenancy/      Mandatory data access wrapper
  packages/contracts/    Generated OpenAPI types
  db/migrations/         Alembic
  infra/terraform/       Modules and per-environment stacks
  evals/                 AI evaluation suites
  docs/                  Already present

Then build packages/tenancy. This is the most important code in the repository, so
build it first and build it carefully. Requirements:

- A single entry point for acquiring a database connection or session
- It takes a resolved scope object: tenant ids, role, principal id
- It issues SET LOCAL app.tenant_ids and SET LOCAL app.role inside the transaction
- SET LOCAL, not SET — explain in a comment why, referencing PgBouncer transaction mode
- Scope must be passed in, never read from ambient context or request state
- A connection acquired any other way must be impossible, not merely discouraged

Add a CI check that fails the build if any file outside packages/tenancy imports the
database driver or creates an engine directly. Make the check part of the repo, not a
suggestion.

Write tests proving: scope is set, scope does not leak between transactions on a
pooled connection, and an empty scope yields zero rows rather than all rows.

Do not write application features yet. Stop when the tenancy package is complete and
tested.
