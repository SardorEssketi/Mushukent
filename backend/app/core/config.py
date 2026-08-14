from functools import lru_cache
from typing import Self

from pydantic import Field, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = Field(default="Mushukistan API", alias="APP_NAME")
    app_env: str = Field(default="development", alias="APP_ENV")
    app_debug: bool = Field(default=False, alias="APP_DEBUG")
    enable_api_docs: bool = Field(default=False, alias="ENABLE_API_DOCS")

    api_prefix: str = Field(default="/api/v1", alias="API_PREFIX")
    cors_allowed_origins: str = Field(default="", alias="CORS_ALLOWED_ORIGINS")

    postgres_db: str = Field(default="mushukistan", alias="POSTGRES_DB")
    postgres_user: str = Field(default="mushukistan", alias="POSTGRES_USER")
    postgres_password: str = Field(default="change_me", alias="POSTGRES_PASSWORD")
    database_url: str = Field(
        default="postgresql+psycopg://mushukistan:mushukistan@db:5432/mushukistan",
        alias="DATABASE_URL",
    )

    jwt_secret_key: str = Field(default="change-me", alias="JWT_SECRET_KEY")
    jwt_algorithm: str = Field(default="HS256", alias="JWT_ALGORITHM")
    jwt_access_token_exp_minutes: int = Field(default=60, alias="JWT_ACCESS_TOKEN_EXP_MINUTES")
    jwt_clock_skew_seconds: int = Field(default=60, alias="JWT_CLOCK_SKEW_SECONDS")
    jwt_issuer: str = Field(default="mushukistan-api", alias="JWT_ISSUER")
    jwt_audience: str = Field(default="mushukistan-mobile", alias="JWT_AUDIENCE")
    email_verification_token_exp_hours: int = Field(
        default=24,
        alias="EMAIL_VERIFICATION_TOKEN_EXP_HOURS",
    )
    public_app_base_url: str = Field(default="", alias="PUBLIC_APP_BASE_URL")
    resend_api_key: str = Field(default="", alias="RESEND_API_KEY")
    resend_from_email: str = Field(
        default="noreply@mushukistan.uz",
        alias="RESEND_FROM_EMAIL",
    )

    rate_limit_enabled: bool = Field(default=True, alias="RATE_LIMIT_ENABLED")
    rate_limit_auth_per_minute: int = Field(default=10, alias="RATE_LIMIT_AUTH_PER_MINUTE")
    rate_limit_anon_per_minute: int = Field(default=30, alias="RATE_LIMIT_ANON_PER_MINUTE")
    rate_limit_public_read_per_minute: int = Field(
        default=180,
        alias="RATE_LIMIT_PUBLIC_READ_PER_MINUTE",
    )
    rate_limit_user_per_minute: int = Field(default=60, alias="RATE_LIMIT_USER_PER_MINUTE")
    rate_limit_upload_per_minute: int = Field(default=10, alias="RATE_LIMIT_UPLOAD_PER_MINUTE")
    rate_limit_backend: str = Field(default="memory", alias="RATE_LIMIT_BACKEND")
    rate_limit_redis_url: str = Field(default="", alias="RATE_LIMIT_REDIS_URL")

    google_oauth_client_id: str = Field(default="", alias="GOOGLE_OAUTH_CLIENT_ID")

    @property
    def google_oauth_client_ids(self) -> list[str]:
        return [
            client_id.strip()
            for client_id in self.google_oauth_client_id.split(",")
            if client_id.strip()
        ]

    r2_account_id: str = Field(default="", alias="R2_ACCOUNT_ID")
    r2_access_key_id: str = Field(default="", alias="R2_ACCESS_KEY_ID")
    r2_secret_access_key: str = Field(default="", alias="R2_SECRET_ACCESS_KEY")
    r2_bucket: str = Field(default="mushukistan-media", alias="R2_BUCKET")
    r2_public_base_url: str = Field(default="", alias="R2_PUBLIC_BASE_URL")
    media_storage_root: str = Field(default=".data/media", alias="MEDIA_STORAGE_ROOT")

    @property
    def is_production_like(self) -> bool:
        return self.app_env.casefold() in {"production", "staging"}

    @property
    def allowed_cors_origins(self) -> list[str]:
        return [
            origin.strip().rstrip("/")
            for origin in self.cors_allowed_origins.split(",")
            if origin.strip()
        ]

    @model_validator(mode="after")
    def validate_production_settings(self) -> Self:
        if not self.is_production_like:
            return self

        insecure_values = {"", "change_me", "change-me", "mushukistan"}
        errors: list[str] = []
        if self.jwt_secret_key in insecure_values or len(self.jwt_secret_key) < 32:
            errors.append("JWT_SECRET_KEY must be set to a strong production secret.")
        if self.postgres_password in insecure_values:
            errors.append("POSTGRES_PASSWORD must be changed for production.")
        if not self.allowed_cors_origins:
            errors.append("CORS_ALLOWED_ORIGINS must include the production frontend origin.")
        if not self.public_app_base_url:
            errors.append("PUBLIC_APP_BASE_URL must be set for email verification links.")
        if not self.resend_api_key:
            errors.append("RESEND_API_KEY must be set for production email delivery.")
        if not self.resend_from_email:
            errors.append("RESEND_FROM_EMAIL must be set to a verified sender address.")
        if errors:
            raise ValueError("Invalid production configuration: " + " ".join(errors))
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
