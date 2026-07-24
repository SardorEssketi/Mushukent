from __future__ import annotations

from fastapi import Header, HTTPException, status


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


def get_bearer_token(authorization: str | None = Header(default=None)) -> str:
    if not authorization:
        raise api_error(
            status.HTTP_401_UNAUTHORIZED,
            "UNAUTHORIZED",
            "Missing or invalid Authorization header.",
        )

    scheme, _, token = authorization.partition(" ")
    if scheme.lower() != "bearer" or not token:
        raise api_error(
            status.HTTP_401_UNAUTHORIZED,
            "UNAUTHORIZED",
            "Missing or invalid Authorization header.",
        )
    return token
