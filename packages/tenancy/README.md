# cloudops-tenancy

The only way application code reaches the platform database (CLAUDE.md rule 1).

```python
from sqlalchemy import select
from cloudops_tenancy import Database, Role, TenantScope

db = Database.from_dsn_file(Path("/mnt/secrets/db-dsn"))     # CSI-mounted, never env or config
scope = TenantScope(tenant_ids, Role.ENGINEER, principal_id)  # resolved server-side (Phase 3)

async with db.transaction(scope) as conn:   # scope applied with SET LOCAL semantics
    rows = await conn.execute(select(resource).where(...))
# committed; scope gone from the server connection
```

## Guarantees and the test that proves each

| Guarantee | How | Test |
| --- | --- | --- |
| Scope is set in the transaction | `set_config(..., true)` before the caller's first statement | `test_scope_is_set_inside_the_transaction` |
| Scope never outlives its transaction on a pooled connection | Transaction-local setting; see the comment in `database.py` | `test_server_connection_carries_no_scope_after_commit_or_rollback` |
| Empty scope sees nothing | `current_tenant_ids()` returns an empty array; RLS matches nothing | `test_empty_scope_yields_zero_rows` |
| Role reaches RLS | `app.role` read by restrictive policies | `test_role_reaches_the_restrictive_policy` |
| Callers cannot change scope or end the transaction | Statement guard + re-verification before commit | `test_statements_that_change_scope_are_refused_before_they_run`, `test_scope_changed_behind_the_guard_is_caught_at_commit` |
| The login role cannot bypass RLS | Checked on every new physical connection | `test_unsafe_roles_are_refused` |
| No other way in | No public engine or connection; CI gate `tools/ci/check_data_access.py` | `tools/ci/tests/test_check_data_access.py` |

Each row has been mutation-checked: removing the mechanism fails its test.

## Running the tests

Integration tests need PostgreSQL 16. Either export a superuser URL, which is
used only to create a throwaway database and roles:

```bash
CLOUDOPS_TEST_ADMIN_DSN=postgresql://postgres:...@localhost:5432/postgres uv run pytest packages/tenancy
```

or have Docker running, and Testcontainers starts `pgvector/pgvector:pg16`. With
neither, the integration tests error. They never skip.
