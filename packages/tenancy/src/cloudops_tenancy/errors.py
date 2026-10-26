"""Errors raised by the tenancy package.

Messages are for operators and logs. They never include tenant ids, customer
names or connection details; callers must still map them to structured error
codes before anything reaches a client.
"""


class TenancyError(Exception):
    """Base class for every error this package raises."""


class InvalidScopeError(TenancyError, ValueError):
    """A ``TenantScope`` was constructed from invalid values."""


class ScopeTamperingError(TenancyError):
    """A statement tried to change scope, session state or transaction state."""


class ScopeClosedError(TenancyError):
    """A ``ScopedConnection`` was used after its transaction ended."""


class UnsafeDatabaseRoleError(TenancyError):
    """The configured database role could bypass row-level security."""
