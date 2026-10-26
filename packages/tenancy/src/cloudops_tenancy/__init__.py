"""cloudops_tenancy — the only way application code reaches the platform database.

Public surface:

    TenantScope, Role       the resolved scope a transaction runs under
    Database                owns the pool; ``transaction(scope)`` is its only door
    ScopedConnection        what that door hands you: execute, scalar — no more
    errors                  TenancyError and subclasses

Result and Row are re-exported for type annotations so callers never need to
import from ``sqlalchemy.engine`` (which CI forbids outside this package).
"""

from sqlalchemy.engine import Result, Row

from cloudops_tenancy.database import Database, ScopedConnection
from cloudops_tenancy.errors import (
    InvalidScopeError,
    ScopeClosedError,
    ScopeTamperingError,
    TenancyError,
    UnsafeDatabaseRoleError,
)
from cloudops_tenancy.scope import Role, TenantScope

__all__ = [
    "Database",
    "InvalidScopeError",
    "Result",
    "Role",
    "Row",
    "ScopeClosedError",
    "ScopeTamperingError",
    "ScopedConnection",
    "TenancyError",
    "TenantScope",
    "UnsafeDatabaseRoleError",
]
