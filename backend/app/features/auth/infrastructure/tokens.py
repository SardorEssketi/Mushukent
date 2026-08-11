from __future__ import annotations

import json
import ssl
from dataclasses import dataclass
from datetime import UTC, datetime, timedelta
from functools import cached_property
from typing import Any
from urllib.request import urlopen
from uuid import UUID

from jose import jwk, jwt
from jose.exceptions import JWTError

from app.core.auth import AccessTokenService, AuthenticatedPrincipal, GoogleIdTokenClaims, Role
from app.core.config import Settings
from app.core.security import api_error

GOOGLE_ISSUERS = {"accounts.google.com", "https://accounts.google.com"}


@dataclass(slots=True)
class _GoogleJwkSet:
    keys: list[dict[str, Any]]


class JoseAccessTokenService(AccessTokenService):
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def issue_access_token(self, principal: AuthenticatedPrincipal) -> str:
        now = datetime.now(UTC)
        expires_at = now + timedelta(minutes=self.settings.jwt_access_token_exp_minutes)
        payload = {
            "sub": str(principal.user_id),
            "role": principal.role.value,
            "iss": self.settings.jwt_issuer,
            "aud": self.settings.jwt_audience,
            "iat": int(now.timestamp()),
            "nbf": int(now.timestamp()),
            "exp": int(expires_at.timestamp()),
            "token_type": "access",
        }

        return jwt.encode(
            payload,
            self.settings.jwt_secret_key,
            algorithm=self.settings.jwt_algorithm,
        )

    def decode_access_token(self, token: str) -> AuthenticatedPrincipal:
        try:
            claims = jwt.decode(
                token,
                self.settings.jwt_secret_key,
                algorithms=[self.settings.jwt_algorithm],
                audience=self.settings.jwt_audience,
                issuer=self.settings.jwt_issuer,
                options={
                    "verify_aud": True,
                    "verify_exp": True,
                    "verify_nbf": True,
                    "verify_iat": False,
                    "leeway": self.settings.jwt_clock_skew_seconds,
                },
            )
        except JWTError as exc:
            raise api_error(401, "UNAUTHORIZED", "Invalid or expired token.") from exc

        if claims.get("token_type") != "access":
            raise api_error(401, "UNAUTHORIZED", "Invalid or expired token.")

        role_value = claims.get("role")
        if role_value not in {role.value for role in Role}:
            raise api_error(401, "UNAUTHORIZED", "Invalid or expired token.")

        subject = claims.get("sub")
        try:
            user_id = UUID(str(subject))
        except (TypeError, ValueError) as exc:
            raise api_error(401, "UNAUTHORIZED", "Invalid or expired token.") from exc

        issued_at = claims.get("iat")
        not_before = claims.get("nbf")
        now = datetime.now(UTC)
        skew = timedelta(seconds=self.settings.jwt_clock_skew_seconds)

        if (
            not isinstance(issued_at, (int, float))
            or datetime.fromtimestamp(float(issued_at), UTC) > now + skew
        ):
            raise api_error(401, "UNAUTHORIZED", "Invalid or expired token.")

        if (
            not isinstance(not_before, (int, float))
            or datetime.fromtimestamp(float(not_before), UTC) > now + skew
        ):
            raise api_error(401, "UNAUTHORIZED", "Invalid or expired token.")

        return AuthenticatedPrincipal(
            user_id=user_id,
            role=Role(role_value),
            is_active=True,
        )


@dataclass(slots=True)
class EmailVerificationClaims:
    user_id: UUID
    email: str


class JoseEmailVerificationTokenService:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings

    def issue_token(self, *, user_id: UUID, email: str) -> str:
        now = datetime.now(UTC)
        expires_at = now + timedelta(hours=self.settings.email_verification_token_exp_hours)
        payload = {
            "sub": str(user_id),
            "email": email,
            "iss": self.settings.jwt_issuer,
            "aud": self.settings.jwt_audience,
            "iat": int(now.timestamp()),
            "nbf": int(now.timestamp()),
            "exp": int(expires_at.timestamp()),
            "token_type": "email_verification",
        }
        return jwt.encode(
            payload,
            self.settings.jwt_secret_key,
            algorithm=self.settings.jwt_algorithm,
        )

    def decode_token(self, token: str) -> EmailVerificationClaims:
        try:
            claims = jwt.decode(
                token,
                self.settings.jwt_secret_key,
                algorithms=[self.settings.jwt_algorithm],
                audience=self.settings.jwt_audience,
                issuer=self.settings.jwt_issuer,
                options={
                    "verify_aud": True,
                    "verify_exp": True,
                    "verify_nbf": True,
                    "verify_iat": False,
                    "leeway": self.settings.jwt_clock_skew_seconds,
                },
            )
        except JWTError as exc:
            raise api_error(
                401,
                "INVALID_VERIFICATION_TOKEN",
                "Invalid or expired verification token.",
            ) from exc

        if claims.get("token_type") != "email_verification":
            raise api_error(
                401,
                "INVALID_VERIFICATION_TOKEN",
                "Invalid or expired verification token.",
            )

        subject = claims.get("sub")
        email = claims.get("email")
        try:
            user_id = UUID(str(subject))
        except (TypeError, ValueError) as exc:
            raise api_error(
                401,
                "INVALID_VERIFICATION_TOKEN",
                "Invalid or expired verification token.",
            ) from exc
        if not isinstance(email, str) or not email:
            raise api_error(
                401,
                "INVALID_VERIFICATION_TOKEN",
                "Invalid or expired verification token.",
            )

        return EmailVerificationClaims(user_id=user_id, email=email)


class GoogleOAuthIdTokenVerifier:
    def __init__(self, settings: Settings) -> None:
        self.settings = settings
        self._jwks_cache: _GoogleJwkSet | None = None

    def verify(self, id_token: str) -> GoogleIdTokenClaims:
        header = jwt.get_unverified_header(id_token)
        if header.get("alg") != "RS256":
            raise api_error(401, "INVALID_GOOGLE_TOKEN", "Invalid Google token.")

        key = self._google_public_key(header.get("kid"))
        try:
            payload = jwt.decode(
                id_token,
                key,
                algorithms=["RS256"],
                audience=self.settings.google_oauth_client_id,
                options={
                    "verify_aud": True,
                    "verify_exp": True,
                    "verify_nbf": True,
                    "verify_iat": False,
                    "leeway": self.settings.jwt_clock_skew_seconds,
                },
            )
        except JWTError as exc:
            raise api_error(401, "INVALID_GOOGLE_TOKEN", "Invalid Google token.") from exc

        issuer = str(payload.get("iss", ""))
        if issuer not in GOOGLE_ISSUERS:
            raise api_error(401, "INVALID_GOOGLE_TOKEN", "Invalid Google token.")

        exp = payload.get("exp")
        if not isinstance(exp, (int, float)):
            raise api_error(401, "INVALID_GOOGLE_TOKEN", "Invalid Google token.")

        return GoogleIdTokenClaims(
            email=payload.get("email"),
            iss=issuer,
            aud=str(payload.get("aud", "")),
            exp=datetime.fromtimestamp(float(exp), UTC),
            sub=payload.get("sub"),
            name=payload.get("name"),
            email_verified=bool(payload.get("email_verified", False)),
            raw=payload,
        )

    def _google_public_key(self, kid: str | None) -> Any:
        if not kid:
            raise api_error(401, "INVALID_GOOGLE_TOKEN", "Invalid Google token.")

        jwks = self._jwks
        for key in jwks.keys:
            if key.get("kid") == kid:
                return jwk.construct(key, algorithm="RS256").to_pem().decode("utf-8")

        raise api_error(401, "INVALID_GOOGLE_TOKEN", "Invalid Google token.")

    @cached_property
    def _jwks(self) -> _GoogleJwkSet:
        if self._jwks_cache is not None:
            return self._jwks_cache

        with urlopen(
            "https://www.googleapis.com/oauth2/v3/certs",
            context=ssl.create_default_context(),
            timeout=10,
        ) as response:
            payload = json.loads(response.read().decode("utf-8"))

        jwks = _GoogleJwkSet(keys=list(payload.get("keys", [])))
        self._jwks_cache = jwks
        return jwks
