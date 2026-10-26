"""Statement guard: application SQL may not alter scope or transaction state.

Every statement sent through a ``ScopedConnection`` passes through here before
it reaches the driver. Without this, any caller holding a scoped connection
could widen its own scope with ``SELECT set_config('app.tenant_ids', ...)`` or
end the scoped transaction with a raw ``COMMIT``.

This is a guard against mistakes, not against hostile code running inside the
process — such code has already won. It is deliberately conservative: a false
positive is a loud failure in development, a false negative is a cross-tenant
read. Scope is additionally re-verified before every commit.
"""

from __future__ import annotations

import re

from cloudops_tenancy.errors import ScopeTamperingError

_BLOCK_COMMENT = re.compile(r"/\*.*?\*/", re.DOTALL)
_LINE_COMMENT = re.compile(r"--[^\n]*")

# Anywhere in a statement: the function form of SET / SET LOCAL.
_ANYWHERE = re.compile(r"\bset_config\b", re.IGNORECASE)

# As the leading keyword of any statement in the text:
#   SET / RESET / DISCARD      change session or transaction settings, incl. SET ROLE
#   BEGIN .. ABORT, PREPARE,
#   COMMIT, ROLLBACK, END      end or replace the scoped transaction
#   DO                         anonymous blocks can build SET/set_config dynamically
_LEADING = re.compile(
    r"^\s*\(?\s*(SET|RESET|DISCARD|BEGIN|START|COMMIT|ROLLBACK|END|ABORT|PREPARE|DO)\b",
    re.IGNORECASE,
)


def check_statement(sql: str) -> None:
    """Raise ``ScopeTamperingError`` if ``sql`` could alter scope or transaction state."""
    stripped = _LINE_COMMENT.sub(" ", _BLOCK_COMMENT.sub(" ", sql))
    if _ANYWHERE.search(stripped):
        raise ScopeTamperingError("set_config is not permitted; the tenancy package owns scope")
    for part in stripped.split(";"):
        match = _LEADING.match(part)
        if match:
            raise ScopeTamperingError(
                f"{match.group(1).upper()} statements are not permitted through a scoped connection"
            )
