from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", env_file_encoding="utf-8", extra="ignore")

    app_name: str = Field(default="Mushukent API", alias="APP_NAME")
    app_env: str = Field(default="development", alias="APP_ENV")
    app_debug: bool = Field(default=False, alias="APP_DEBUG")

    api_prefix: str = Field(default="/api/v1", alias="API_PREFIX")

    postgres_db: str = Field(default="mushukent", alias="POSTGRES_DB")
    postgres_user: str = Field(default="mushukent", alias="POSTGRES_USER")
    postgres_password: str = Field(default="change_me", alias="POSTGRES_PASSWORD")
    database_url: str = Field(
        default="postgresql+psycopg://mushukent:mushukent@db:5432/mushukent",
        alias="DATABASE_URL",
    )

    jwt_secret_key: str = Field(default="change-me", alias="JWT_SECRET_KEY")
    jwt_algorithm: str = Field(default="HS256", alias="JWT_ALGORITHM")
    jwt_access_token_exp_minutes: int = Field(default=60, alias="JWT_ACCESS_TOKEN_EXP_MINUTES")
    jwt_clock_skew_seconds: int = Field(default=60, alias="JWT_CLOCK_SKEW_SECONDS")
    jwt_issuer: str = Field(default="mushukent-api", alias="JWT_ISSUER")
    jwt_audience: str = Field(default="mushukent-mobile", alias="JWT_AUDIENCE")

    google_oauth_client_id: str = Field(default="", alias="GOOGLE_OAUTH_CLIENT_ID")

    r2_account_id: str = Field(default="", alias="R2_ACCOUNT_ID")
    r2_access_key_id: str = Field(default="", alias="R2_ACCESS_KEY_ID")
    r2_secret_access_key: str = Field(default="", alias="R2_SECRET_ACCESS_KEY")
    r2_bucket: str = Field(default="mushukent-media", alias="R2_BUCKET")
    r2_public_base_url: str = Field(default="", alias="R2_PUBLIC_BASE_URL")


@lru_cache
def get_settings() -> Settings:
    return Settings()
