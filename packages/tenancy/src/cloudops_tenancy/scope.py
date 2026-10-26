"""The resolved tenant scope a database transaction runs under.

A ``TenantScope`` is a value, not a lookup. It is resolved server-side from the
authenticated principal (Phase 3) and passed explicitly to
``Database.transaction``. Nothing in this package reads scope from a context
variable, a request object, a header or a token claim — if the caller does not
hand a scope over, there is no scope.
"""

from __future__ import annotations

import enum
from collections.abc import Iterable
from dataclasses import dataclass
from uuid import UUID

from cloudops_tenancy.errors import InvalidScopeError


class Role(enum.StrEnum):
    """Platform roles that row-level security policies key on via ``app.role``.

    Values are the strings the policies compare against, so renaming one is a
    database migration, not a refactor. The set is the roles named in the LLD
    and reference schema; customer-facing roles are not yet specified (open for
    Phase 3) and are deliberately absent rather than guessed.
    """

    CEO = "ceo"
    CFO = "cfo"
    FINOPS = "finops"
    SECOPS = "secops"
    DELIVERY_LEAD = "delivery_lead"
    COMMERCIAL = "commercial"
    AUDITOR = "auditor"
    PLATFORM_ADMIN = "platform_admin"
    ENGINEER = "engineer"


@dataclass(frozen=True, slots=True)
class TenantScope:
    """Tenants, role and principal a single transaction is allowed to act as.

    An empty ``tenant_ids`` is valid and means "no tenant": every tenant-scoped
    table returns zero rows. It never means "all tenants".
    """

    tenant_ids: frozenset[UUID]
    role: Role
    principal_id: str

    def __init__(self, tenant_ids: Iterable[UUID], role: Role, principal_id: str) -> None:
        # Strings are iterable; a bare tenant id string would otherwise be split
        # into characters and then fail obscurely, or worse, partially succeed.
        if isinstance(tenant_ids, str | bytes):
            raise InvalidScopeError("tenant_ids must be a collection of UUIDs, not a string")
        ids = frozenset(tenant_ids)
        if not all(type(t) is UUID for t in ids):
            raise InvalidScopeError("tenant_ids must contain only uuid.UUID values")
        if type(role) is not Role:
            raise InvalidScopeError("role must be a Role member")
        if not isinstance(principal_id, str) or not principal_id.strip():
            raise InvalidScopeError("principal_id must be a non-empty string")
        if not principal_id.isprintable():
            raise InvalidScopeError("principal_id must not contain control characters")
        object.__setattr__(self, "tenant_ids", ids)
        object.__setattr__(self, "role", role)
        object.__setattr__(self, "principal_id", principal_id)

    @property
    def tenant_ids_setting(self) -> str:
        """``app.tenant_ids`` as ``cloudops.current_tenant_ids()`` parses it.

        Comma-separated, sorted so the same scope always produces the same
        string. Empty scope is the empty string, which the function maps to an
        empty array.
        """
        return ",".join(sorted(str(t) for t in self.tenant_ids))
