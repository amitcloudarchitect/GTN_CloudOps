# Phase 5 — AI gateway and tool registry

Read these first: `docs/LLD.md`, `docs/HLD.md`

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
