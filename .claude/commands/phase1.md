# Phase 1 — Database schema and migrations

Read these first: `docs/LLD.md`, `reference/schema.sql`, `docs/03-data-mapping.png`

Build the database layer from reference/schema.sql and the LLD's database design
section.

Use Alembic. The first migration creates the core entities: tenant, tenant_alias, sow,
cloud_account, resource, work_item, cost_fact, vulnerability, knowledge_chunk,
audit.action_log, fx_rate, ingest_watermark, and the quarantine tables.

For every table carrying customer data:
- tenant_id column, not nullable
- ENABLE and FORCE row level security
- A tenant_isolation policy using and checking cloudops.current_tenant_ids()
- The commercial tables additionally get the restrictive commercial_visibility policy

Partition cost_fact monthly, work_item quarterly, audit.action_log monthly. Use
pg_partman. Revoke UPDATE and DELETE on audit.action_log.

Add the fx_rate table and the to_currency() function exactly as specified — note the
rate_type argument is required, not defaulted, so a caller must decide between closing
and average.

Migrations must be expand-then-contract. Set lock_timeout to 3s. Use CREATE INDEX
CONCURRENTLY.

Then write the isolation test suite. It must include every case in the LLD's "isolation
cases that must exist" table. These tests are a release gate, so structure them so CI
can run them as a named suite.
