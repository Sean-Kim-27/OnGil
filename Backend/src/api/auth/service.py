from dataclasses import dataclass
from typing import Any, Optional

import httpx
from sqlalchemy import select
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session

from api.auth.models import User
from api.auth.schemas import SocialProvider
from core.config import settings

GOOGLE_USERINFO_URL = "https://openidconnect.googleapis.com/v1/userinfo"
GOOGLE_TOKENINFO_URL = "https://oauth2.googleapis.com/tokeninfo"
KAKAO_USERINFO_URL = "https://kapi.kakao.com/v2/user/me"


class InvalidSocialTokenError(ValueError):
    """Raised when neither supported provider accepts a social token."""


class SocialProviderUnavailableError(RuntimeError):
    """Raised when provider availability prevents token verification."""


class _UpstreamUnavailableError(RuntimeError):
    pass


@dataclass(frozen=True)
class SocialProfile:
    provider: SocialProvider
    social_id: str
    email: Optional[str] = None
    nickname: Optional[str] = None
    profile_image_url: Optional[str] = None


class SocialTokenVerifier:
    """Resolve an opaque client token by asking the supported providers."""

    def __init__(self, client: Optional[httpx.Client] = None) -> None:
        self._client = client

    def verify(self, token: str) -> SocialProfile:
        if not token.strip():
            raise InvalidSocialTokenError("소셜 로그인 토큰이 비어 있습니다.")

        owns_client = self._client is None
        client = self._client or httpx.Client(
            timeout=settings.SOCIAL_PROVIDER_TIMEOUT_SECONDS,
            follow_redirects=False,
        )
        unavailable_count = 0

        try:
            for verifier in (self._verify_google, self._verify_kakao):
                try:
                    profile = verifier(client, token)
                except (httpx.RequestError, _UpstreamUnavailableError):
                    unavailable_count += 1
                    continue
                if profile is not None:
                    return profile
        finally:
            if owns_client:
                client.close()

        if unavailable_count:
            raise SocialProviderUnavailableError(
                "소셜 로그인 공급자에 연결할 수 없습니다."
            )
        raise InvalidSocialTokenError("Google 또는 Kakao에서 유효하지 않은 토큰입니다.")

    def _verify_google(
        self, client: httpx.Client, token: str
    ) -> Optional[SocialProfile]:
        if token.count(".") == 2:
            response = client.get(GOOGLE_TOKENINFO_URL, params={"id_token": token})
            payload = self._accepted_payload(response)
            if payload is not None:
                expected_audience = settings.GOOGLE_CLIENT_ID
                if expected_audience and payload.get("aud") != expected_audience:
                    return None
                return self._google_profile(payload)

        response = client.get(
            GOOGLE_USERINFO_URL,
            headers={"Authorization": f"Bearer {token}"},
        )
        payload = self._accepted_payload(response)
        return self._google_profile(payload) if payload is not None else None

    def _verify_kakao(
        self, client: httpx.Client, token: str
    ) -> Optional[SocialProfile]:
        response = client.get(
            KAKAO_USERINFO_URL,
            headers={"Authorization": f"Bearer {token}"},
        )
        payload = self._accepted_payload(response)
        if payload is None or payload.get("id") is None:
            return None

        account = payload.get("kakao_account") or {}
        profile = account.get("profile") or {}
        properties = payload.get("properties") or {}
        return SocialProfile(
            provider=SocialProvider.KAKAO,
            social_id=str(payload["id"]),
            email=account.get("email"),
            nickname=profile.get("nickname") or properties.get("nickname"),
            profile_image_url=(
                profile.get("profile_image_url") or properties.get("profile_image")
            ),
        )

    @staticmethod
    def _accepted_payload(response: httpx.Response) -> Optional[dict[str, Any]]:
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
    def _google_profile(payload: dict[str, Any]) -> Optional[SocialProfile]:
        social_id = payload.get("sub")
        if not social_id:
            return None
        return SocialProfile(
            provider=SocialProvider.GOOGLE,
            social_id=str(social_id),
            email=payload.get("email"),
            nickname=payload.get("name"),
            profile_image_url=payload.get("picture"),
        )


def login_or_signup(
    db: Session,
    token: str,
    verifier: Optional[SocialTokenVerifier] = None,
) -> tuple[User, bool]:
    """Verify a social token, then return or create the matching user."""
    profile = (verifier or SocialTokenVerifier()).verify(token)
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
