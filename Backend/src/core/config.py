from typing import Literal

from pydantic import Field, SecretStr
from pydantic_settings import BaseSettings, SettingsConfigDict


class Settings(BaseSettings):
    model_config = SettingsConfigDict(env_file=".env", extra="ignore")

    DATABASE_URL: str
    GOOGLE_CLIENT_ID: str = Field(min_length=10)
    KAKAO_APP_ID: int = Field(gt=0)
    JWT_SECRET_KEY: SecretStr = Field(min_length=32)

    ACCESS_TOKEN_EXPIRE_MINUTES: int = Field(default=15, ge=5, le=60)
    REFRESH_TOKEN_EXPIRE_DAYS: int = Field(default=30, ge=1, le=90)
    JWT_ALGORITHM: Literal["HS256"] = "HS256"
    JWT_ISSUER: str = "ongil-api"

    SOCIAL_PROVIDER_TIMEOUT_SECONDS: float = Field(default=5.0, gt=0, le=15)
    SOCIAL_LOGIN_RATE_LIMIT: int = Field(default=10, ge=1, le=100)
    SOCIAL_LOGIN_RATE_WINDOW_SECONDS: int = Field(default=60, ge=10, le=3600)
    MAX_REQUEST_BODY_BYTES: int = Field(default=16384, ge=1024, le=1048576)

    KOR_SERVICE_BASE_URL: str | None = None
    KOR_RELATE_BASE_URL: str | None = None
    KOR_DATA_API_KEY: SecretStr | None = None
    TOUR_API_TIMEOUT_SECONDS: float = Field(default=8.0, gt=0, le=30)
    TOUR_API_PAGE_SIZE: int = Field(default=100, ge=10, le=1000)
    TOUR_API_MAX_RESULTS_PER_CATEGORY: int = Field(default=2000, ge=100, le=10000)

    REDIS_URL: str | None = None
    ENVIRONMENT: str = "development"
    ALLOWED_HOSTS: str = "localhost,127.0.0.1,testserver"
    ENABLE_DOCS: bool = True
    FORCE_HTTPS: bool = False

    @property
    def allowed_hosts(self) -> list[str]:
        return [host.strip() for host in self.ALLOWED_HOSTS.split(",") if host.strip()]

    @property
    def is_production(self) -> bool:
        return self.ENVIRONMENT.lower() == "production"


settings = Settings()
