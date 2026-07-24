from __future__ import annotations

from collections.abc import Mapping
from enum import StrEnum
from typing import Protocol

from fastapi import HTTPException, status

from app.core.auth import AuthenticatedPrincipal, Role


class Permission(StrEnum):
    CREATE_POST = "create_post"
    CREATE_COMMENT = "create_comment"
    CREATE_REPORT = "create_report"
    UPDATE_OWN_PROFILE = "update_own_profile"
    DELETE_OWN_CONTENT = "delete_own_content"
    VIEW_MODERATION_QUEUE = "view_moderation_queue"
    RESOLVE_REPORTS = "resolve_reports"
    REMOVE_CONTENT = "remove_content"
    SUSPEND_USERS = "suspend_users"


ROLE_PERMISSIONS: Mapping[Role, frozenset[Permission]] = {
    Role.USER: frozenset(
        {
            Permission.CREATE_POST,
            Permission.CREATE_COMMENT,
            Permission.CREATE_REPORT,
            Permission.UPDATE_OWN_PROFILE,
            Permission.DELETE_OWN_CONTENT,
        }
    ),
    Role.MODERATOR: frozenset(Permission),
}


class AuthorizationService(Protocol):
    """RBAC contract for feature and API layers."""

    def has_role(self, principal: AuthenticatedPrincipal, role: Role) -> bool: ...

    def has_permission(self, principal: AuthenticatedPrincipal, permission: Permission) -> bool: ...

    def assert_permission(
        self,
        principal: AuthenticatedPrincipal,
        permission: Permission,
    ) -> None: ...


class RoleBasedAuthorizationService:
    def has_role(self, principal: AuthenticatedPrincipal, role: Role) -> bool:
        return principal.role == role

    def has_permission(self, principal: AuthenticatedPrincipal, permission: Permission) -> bool:
        if principal.role == Role.MODERATOR:
            return True
        return permission in ROLE_PERMISSIONS.get(principal.role, frozenset())

    def assert_permission(
        self,
        principal: AuthenticatedPrincipal,
        permission: Permission,
    ) -> None:
        if self.has_permission(principal, permission):
            return
        raise HTTPException(
            status_code=status.HTTP_403_FORBIDDEN,
            detail={
                "success": False,
                "error": {
                    "code": "FORBIDDEN",
                    "message": "You do not have permission to perform this action.",
                },
            },
        )
