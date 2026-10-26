# Build phases, in order

One phase per session. Use `/clear` between them.

Each phase is also a slash command — type `/phase0`, `/phase1` and so on rather than
pasting. The "Read these first" line tells Claude Code which files to open; it has
filesystem access, so it reads them itself rather than you attaching anything.

A note on how these are written: each gives Claude Code the goal, the constraints it must
not break, and what "done" looks like. Vague prompts produce confident, wrong code —
especially in a codebase where the wrong code is a data leak rather than a crash.

---

## Phase 0 — Scaffold and the tenancy package

**Read first:** `docs/LLD.md`, `reference/schema.sql`

```
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
```

---

## Phase 1 — Database schema and migrations

**Read first:** `docs/LLD.md`, `reference/schema.sql`, `docs/03-data-mapping.png`

```
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
```

---

## Phase 2 — Terraform foundation

**Read first:** `docs/LLD.md`, `docs/01-system-design.png`, `AZURE-ACCESS.md`

```
Write the Terraform for the development environment.

Important constraint: I am building in a SINGLE Azure subscription for development,
not the five-subscription model in the LLD. Use resource groups for separation, with
the subscription id as a variable per stack, so moving to five subscriptions later is
configuration rather than rework.

Stacks, in this order — each must apply cleanly before the next:
  1. infra/terraform/stacks/01-network     VNet, subnets, NSGs, private DNS zones, NAT
  2. infra/terraform/stacks/02-security    Key Vault, Key Vault Premium, managed identities
  3. infra/terraform/stacks/03-observability  Log Analytics, Application Insights
  4. infra/terraform/stacks/04-data        PostgreSQL Flexible Server, Redis, storage, Event Hubs
  5. infra/terraform/stacks/05-aks         AKS with node pools, excluding npexec

Follow the LLD exactly for naming, address space, SKUs and settings. Specifically:
- PostgreSQL with the parameter overrides in the LLD, pgvector enabled
- All data services with public network access disabled and private endpoints
- Storage accounts with shared key access disabled, Entra ID auth only
- AKS private cluster, Workload Identity, no local accounts, Azure CNI overlay
- Mandatory tags on every resource, enforced by a module that refuses to omit them

Backend: azurerm with use_azuread_auth = true. No storage account key anywhere.

Run terraform init and terraform plan for stack 01 and show me the plan.
DO NOT run terraform apply — I will run it myself after reviewing.
```

Run `apply` yourself, then continue stack by stack in the same session.

---

## Phase 3 — API skeleton and scope resolution

**Read first:** `docs/LLD.md`, `docs/05-request-lifecycle.png`

```
Build the API application skeleton and, most importantly, scope resolution.

FastAPI. Entra ID token validation. The request lifecycle is in the attached diagram
and the LLD — follow it exactly.

Scope resolution is the security-critical part:
- Validate the token signature and claims properly, not superficially
- Resolve the principal to an organisation and role from the database
- Resolve the tenant set server-side from the assignment table
- NEVER read tenant scope from a token claim, header or query parameter
- A customer principal must resolve to exactly one tenant; any other result is a defect
  and must raise, not degrade gracefully

Then build the BFF layer that shapes responses per role and rejects anything outside
the permission matrix in the HLD.

Every metric in a response carries provenance: value, unit, source_system, as_of,
query_ref, is_modelled. Build this into the response model so it cannot be forgotten.

Add the audit log write on every access.

Write tests including: a tampered organisation claim is ignored, a customer principal
cannot reach another tenant, and a request with no valid scope fails closed.
```

---

## Phase 4 — First connector, end to end

**Read first:** `docs/LLD.md`, `docs/02-integration-map.png`

```
Build the ServiceNow READ connector, end to end, as the reference implementation that
every other connector will copy.

I do not have ServiceNow credentials yet. Build against recorded fixtures — create
realistic fixture files with the field names from the LLD's ServiceNow mapping, with
anonymised data. The connector must work identically against fixtures and a real
instance.

Implement the full connector contract from the LLD:
  authenticate → watermark → fetch with 5-minute overlap → persist raw to blob
  → normalise → resolve identity → quarantine unmatched → commit transactionally
  → report health

Specific requirements:
- Raw payload written to blob BEFORE any parsing, partitioned source/entity/yyyy/mm/dd
- Watermark advances inside the same transaction that commits the batch
- Unknown source fields retained in raw_extra jsonb rather than discarded
- Identity resolution: exact alias match, then normalised, then quarantine — never guess
- Rate limit handling honouring X-RateLimit-Remaining
- A replay path that reprocesses from blob without re-fetching

Orchestrate with Temporal. The connector is a workflow, not a cron job.

Write contract tests against the fixtures and an integration test using Testcontainers
for PostgreSQL.

Document the connector contract as a short README so the next five connectors follow it.
```

---

## Phase 5 — AI gateway and tool registry

**Read first:** `docs/LLD.md`, `docs/HLD.md`

```
Build the AI gateway and the tool registry. No agents yet — just the infrastructure
they will run on.

Gateway requirements from the LLD:
- Three model tiers behind deployment aliases: small, large, embed
- Application code names a TIER, never a model
- Redaction of personal data and secrets BEFORE any model call
- Per-user and per-tenant token quotas
- Semantic response cache
- Full tracing: prompt, retrieval set, tool calls, tokens, latency, cost per request
- Spend circuit breaker
- Agent loop ceiling of 10 tool iterations, then escalate
- Fallback to the secondary provider on throttling, and to small if large is unavailable

Tool registry:
- Each tool declares name, JSON Schema, required role, read-or-write, tenant scope
  requirement, idempotency key need, timeout
- The gateway authorises BEFORE the call reaches any service
- Arguments are schema-validated; an invalid argument is a refusal, not best-effort
- Tenant scope resolved server-side, never from a model-supplied argument
- The model never receives a credential or a database connection

Implement three read-only tools to prove the pattern: get_resource_context,
search_tickets, get_cost_trend.

Then build the retrieval layer: chunking, embedding, pgvector with HNSW, hybrid search
fusing vector and full-text by reciprocal rank. The tenant predicate goes INSIDE the
SQL query.

Write a test proving an adversarial query naming another customer returns no foreign
chunks.
```

---

## Phase 6 — Classifier agent and the evaluation harness

**Read first:** `docs/LLD.md`, `docs/04-remediation-workflow.png`

```
Build the evaluation harness FIRST, then the classifier agent. In that order — I want
to be able to measure the agent from its first commit.

Evaluation harness:
- A golden set of tickets with known-correct intent, CI, action class
- Scoring for classification accuracy, groundedness, refusal correctness
- Adversarial cases: prompt injection in ticket text, cross-tenant retrieval attempts
- Runs as a CI job that fails on regression against a stored baseline
- Structured so new cases are added from production corrections

Then the classifier agent:
- Small model tier
- NO tools at all — it classifies, nothing else
- Typed, schema-validated output: intent, affected CI, customer, action class,
  risk rating, confidence
- Low confidence routes to a human rather than guessing
- Ticket text is DATA — extract structured intent, never follow instructions in it

Then the enricher agent: read-only tools only, assembles a structured context bundle.

Wire both into a Temporal workflow implementing stages 1 to 3 of the remediation
pipeline. Stages 4 onward come later.

Do not build the planner, the execution plane, or anything that can act on a customer
environment. Those need a security review first.
```

---

## Phase 7 onward

By this point Claude Code has the patterns and you can be briefer. Remaining work:

- Operations console (Next.js, the role-driven layouts from the HLD)
- Remaining read connectors — Qualys, CoreStack, Azure, AWS, SharePoint
- Telemetry streaming path into the column store
- FinOps: billing ingest, charge classification, invoice reconciliation
- Pricing engine integration — `reference/pricing_engine.py` is already written and
  regression-tested; port it, do not rewrite it
- Margin and contribution
- Reporting pack generation
- Customer portal

**The execution plane is last**, and only after a human has reviewed the broker design
against the threat model in the HLD.

---

## Prompts that will not work

For contrast, so you can see the shape to avoid:

> "Build the CloudOps platform from the attached design."

Too large. You will get a plausible-looking skeleton with the hard parts stubbed and
the security properties absent.

> "Add a quick endpoint to fetch all resources."

"All" across tenants is exactly the bug the design exists to prevent. Always phrase
data access in terms of the scoped principal.

> "Just hard-code the connection string for now."

Nothing is more permanent than a temporary secret.

## When it goes wrong

Three failure modes to watch for:

**It bypasses the tenancy package** because a direct query was simpler. The CI check
from Phase 0 catches this — which is why that check is built first.

**It invents a design detail** rather than saying it is unspecified. Ask "where in the
LLD is this specified?" and it will usually admit it guessed.

**It drifts across a long session.** Use `/clear` between phases. If output quality
drops mid-phase, clear and restart the phase — CLAUDE.md reloads automatically, so you
lose nothing but the drift.
