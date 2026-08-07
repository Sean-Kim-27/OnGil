from dataclasses import dataclass
from typing import Any

import httpx
from google.auth.exceptions import TransportError
from google.auth.transport.requests import Request as GoogleRequest
from google.oauth2 import id_token as google_id_token
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from api.auth.models import User
from api.auth.schemas import SocialProvider
from core.config import settings

GOOGLE_ISSUERS = {"accounts.google.com", "https://accounts.google.com"}
KAKAO_INTROSPECTION_URL = "https://kapi.kakao.com/v1/user/access_token_info"
KAKAO_USERINFO_URL = "https://kapi.kakao.com/v2/user/me"


class InvalidSocialTokenError(ValueError):
    """Raised when neither supported provider accepts a social token."""


class SocialProviderUnavailableError(RuntimeError):
    """Raised when provider availability prevents token verification."""


class _UpstreamUnavailableError(RuntimeError):
    pass


class _GoogleRequestWithTimeout:
    def __init__(self) -> None:
        self._request = GoogleRequest()

    def __call__(
        self,
        url: str,
        method: str = "GET",
        body: bytes | None = None,
        headers: dict[str, str] | None = None,
        timeout: float = 120,
        **kwargs: Any,
    ) -> Any:
        return self._request(
            url=url,
            method=method,
            body=body,
            headers=headers,
            timeout=min(timeout, settings.SOCIAL_PROVIDER_TIMEOUT_SECONDS),
            **kwargs,
        )


@dataclass(frozen=True)
class SocialProfile:
    provider: SocialProvider
    social_id: str
    email: str | None = None
    nickname: str | None = None
    profile_image_url: str | None = None


class SocialTokenVerifier:
    """Verify a token only against the provider explicitly chosen by the client."""

    def __init__(
        self,
        client: httpx.Client | None = None,
        google_request: GoogleRequest | _GoogleRequestWithTimeout | None = None,
    ) -> None:
        self._client = client
        self._google_request = google_request

    def verify(self, provider: SocialProvider, token: str) -> SocialProfile:
        if not token.strip():
            raise InvalidSocialTokenError("소셜 로그인 토큰이 비어 있습니다.")

        if provider is SocialProvider.GOOGLE:
            return self._verify_google(token)

        owns_client = self._client is None
        client = self._client or self._new_http_client()
        try:
            try:
                profile = self._verify_kakao(client, token)
            except (httpx.RequestError, _UpstreamUnavailableError) as exc:
                raise SocialProviderUnavailableError(
                    "소셜 로그인 공급자에 연결할 수 없습니다."
                ) from exc
            if profile is not None:
                return profile
        finally:
            if owns_client:
                client.close()

        raise InvalidSocialTokenError(f"{provider.value}에서 유효하지 않은 토큰입니다.")

    def _verify_google(self, token: str) -> SocialProfile:
        try:
            payload = google_id_token.verify_oauth2_token(
                token,
                self._google_request or _GoogleRequestWithTimeout(),
                audience=settings.GOOGLE_CLIENT_ID,
            )
        except TransportError as exc:
            raise SocialProviderUnavailableError(
                "Google 토큰 검증 서비스를 사용할 수 없습니다."
            ) from exc
        except ValueError as exc:
            raise InvalidSocialTokenError(
                "Google에서 유효하지 않은 ID token입니다."
            ) from exc

        if (
            payload.get("iss") not in GOOGLE_ISSUERS
            or payload.get("aud") != settings.GOOGLE_CLIENT_ID
            or not payload.get("sub")
            or payload.get("exp") is None
        ):
            raise InvalidSocialTokenError(
                "Google ID token의 필수 검증값이 올바르지 않습니다."
            )
        profile = self._google_profile(payload)
        if profile is None:
            raise InvalidSocialTokenError("Google 사용자 식별자가 없습니다.")
        return profile

    def _verify_kakao(self, client: httpx.Client, token: str) -> SocialProfile | None:
        authorization = {"Authorization": f"Bearer {token}"}
        token_response = client.get(
            KAKAO_INTROSPECTION_URL,
            headers=authorization,
        )
        token_payload = self._accepted_payload(token_response)
        if token_payload is None:
            return None

        token_user_id = token_payload.get("id")
        try:
            expires_in = int(token_payload.get("expires_in", 0))
        except (TypeError, ValueError):
            return None
        if (
            token_user_id is None
            or str(token_payload.get("app_id")) != str(settings.KAKAO_APP_ID)
            or expires_in <= 0
        ):
            return None

        response = client.get(
            KAKAO_USERINFO_URL,
            headers=authorization,
        )
        payload = self._accepted_payload(response)
        if payload is None or str(payload.get("id")) != str(token_user_id):
            return None

        account = payload.get("kakao_account") or {}
        profile = account.get("profile") or {}
        properties = payload.get("properties") or {}
        return SocialProfile(
            provider=SocialProvider.KAKAO,
            social_id=str(payload["id"]),
            email=(
                account.get("email")
                if account.get("is_email_valid") and account.get("is_email_verified")
                else None
            ),
            nickname=profile.get("nickname") or properties.get("nickname"),
            profile_image_url=(
                profile.get("profile_image_url") or properties.get("profile_image")
            ),
        )

    @staticmethod
    def _accepted_payload(response: httpx.Response) -> dict[str, Any] | None:
        if response.status_code in (400, 401, 403):
            return None
        if response.status_code == 429 or response.status_code >= 500:
            raise _UpstreamUnavailableError
        if response.status_code != 200:
            return None
        try:
            payload = response.json()
        except ValueError:
            return None
        return payload if isinstance(payload, dict) else None

    @staticmethod
    def _google_profile(payload: dict[str, Any]) -> SocialProfile | None:
        social_id = payload.get("sub")
        if not social_id:
            return None
        return SocialProfile(
            provider=SocialProvider.GOOGLE,
            social_id=str(social_id),
            email=payload.get("email") if payload.get("email_verified") else None,
            nickname=payload.get("name"),
            profile_image_url=payload.get("picture"),
        )

    @staticmethod
    def _new_http_client() -> httpx.Client:
        return httpx.Client(
            timeout=settings.SOCIAL_PROVIDER_TIMEOUT_SECONDS,
            follow_redirects=False,
        )


def login_or_signup(
    db: Session,
    provider: SocialProvider,
    token: str,
    verifier: SocialTokenVerifier | None = None,
) -> tuple[User, bool]:
    """Verify a social token, then return or create the matching user."""
    profile = (verifier or SocialTokenVerifier()).verify(provider, token)
    if profile.provider != provider:
        raise InvalidSocialTokenError("요청한 소셜 로그인 공급자와 토큰이 다릅니다.")
    query = select(User).where(
        User.social_provider == profile.provider.value,
        User.social_id == profile.social_id,
    )
    existing_user = db.scalar(query)
    if existing_user is not None:
        return existing_user, False

    user = User(
        social_provider=profile.provider.value,
        social_id=profile.social_id,
        email=profile.email,
        nickname=profile.nickname,
        profile_image_url=profile.profile_image_url,
        status="PENDING",
    )
    db.add(user)

    try:
        db.commit()
    except IntegrityError:
        db.rollback()
        concurrent_user = db.scalar(query)
        if concurrent_user is None:
            raise
        return concurrent_user, False

    db.refresh(user)
    return user, True
