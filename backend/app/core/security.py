from __future__ import annotations

from fastapi import HTTPException, Security, status
from fastapi.security import HTTPAuthorizationCredentials, HTTPBearer

_bearer_scheme = HTTPBearer(auto_error=False)


def api_error(
    status_code: int,
    code: str,
    message: str,
    details: object | None = None,
) -> HTTPException:
    payload: dict[str, object] = {
        "success": False,
        "error": {
            "code": code,
            "message": message,
        },
    }
    if details is not None:
        payload["error"]["details"] = details  # type: ignore[index]
    return HTTPException(status_code=status_code, detail=payload)


def _extract_bearer_token(credentials: HTTPAuthorizationCredentials | None) -> str | None:
    if credentials is None:
        return None
    if credentials.scheme.lower() != "bearer" or not credentials.credentials:
        return None
    return credentials.credentials


def get_optional_bearer_token(authorization: str | None) -> str | None:
    if authorization is None:
        return None
    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise api_error(
            status.HTTP_401_UNAUTHORIZED,
            "UNAUTHORIZED",
            "Missing or invalid Authorization header.",
        )
    return token


def get_bearer_token(
    credentials: HTTPAuthorizationCredentials | None = Security(_bearer_scheme),
) -> str:
    token = _extract_bearer_token(credentials)
    if token is None:
        raise api_error(
            status.HTTP_401_UNAUTHORIZED,
            "UNAUTHORIZED",
            "Missing or invalid Authorization header.",
        )
    return token
