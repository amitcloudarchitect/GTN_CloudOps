# Phase 4 — First connector, end to end

Read these first: `docs/LLD.md`, `docs/02-integration-map.png`

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
