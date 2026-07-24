from __future__ import annotations

from passlib.context import CryptContext

from app.core.auth import PasswordHasher


class PasslibPasswordHasher(PasswordHasher):
    def __init__(self) -> None:
        self._context = CryptContext(
            schemes=["argon2", "bcrypt"],
            default="argon2",
            deprecated="auto",
        )

    def hash_password(self, password: str) -> str:
        return self._context.hash(password)

    def verify_password(self, password: str, password_hash: str) -> bool:
        return self._context.verify(password, password_hash)
