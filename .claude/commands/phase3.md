# Phase 3 — API skeleton and scope resolution

Read these first: `docs/LLD.md`, `docs/05-request-lifecycle.png`

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
