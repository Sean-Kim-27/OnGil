import os
import unittest

os.environ.setdefault("DATABASE_URL", "sqlite://")

import httpx
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from api.auth.models import User
from api.auth.schemas import SocialProvider
from api.auth.service import (
    GOOGLE_TOKENINFO_URL,
    GOOGLE_USERINFO_URL,
    KAKAO_USERINFO_URL,
    InvalidSocialTokenError,
    SocialProfile,
    SocialTokenVerifier,
    login_or_signup,
)
from core.database import Base


class FakeVerifier:
    def __init__(self, profile: SocialProfile) -> None:
        self.profile = profile

    def verify(self, token: str) -> SocialProfile:
        return self.profile


class SocialTokenVerifierTests(unittest.TestCase):
    def test_distinguishes_kakao_access_token(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            if str(request.url) == GOOGLE_USERINFO_URL:
                return httpx.Response(401, json={"error": "invalid_token"})
            if str(request.url) == KAKAO_USERINFO_URL:
                return httpx.Response(
                    200,
                    json={
                        "id": 12345,
                        "kakao_account": {
                            "email": "kakao@example.com",
                            "profile": {"nickname": "카카오 사용자"},
                        },
                    },
                )
            raise AssertionError(f"Unexpected URL: {request.url}")

        client = httpx.Client(transport=httpx.MockTransport(handler))
        profile = SocialTokenVerifier(client).verify("kakao-access-token")

        self.assertEqual(profile.provider, SocialProvider.KAKAO)
        self.assertEqual(profile.social_id, "12345")
        self.assertEqual(profile.email, "kakao@example.com")

    def test_accepts_google_id_token(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            self.assertEqual(str(request.url).split("?", 1)[0], GOOGLE_TOKENINFO_URL)
            return httpx.Response(
                200,
                json={
                    "sub": "google-user-1",
                    "email": "google@example.com",
                    "name": "Google User",
                },
            )

        client = httpx.Client(transport=httpx.MockTransport(handler))
        profile = SocialTokenVerifier(client).verify("header.payload.signature")

        self.assertEqual(profile.provider, SocialProvider.GOOGLE)
        self.assertEqual(profile.social_id, "google-user-1")

    def test_rejects_token_unknown_to_both_providers(self) -> None:
        client = httpx.Client(
            transport=httpx.MockTransport(
                lambda request: httpx.Response(401, json={"error": "invalid_token"})
            )
        )

        with self.assertRaises(InvalidSocialTokenError):
            SocialTokenVerifier(client).verify("unknown-token")


class LoginOrSignupTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine, tables=[User.__table__])
        self.db = Session(self.engine)
        self.profile = SocialProfile(
            provider=SocialProvider.GOOGLE,
            social_id="google-user-1",
            email="user@example.com",
            nickname="User",
        )

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def test_inserts_user_on_first_login(self) -> None:
        user, is_new_user = login_or_signup(
            self.db,
            "valid-token",
            verifier=FakeVerifier(self.profile),
        )

        user_count = self.db.scalar(select(func.count()).select_from(User))
        self.assertTrue(is_new_user)
        self.assertEqual(user_count, 1)
        self.assertEqual(user.social_provider, "GOOGLE")
        self.assertEqual(user.status, "PENDING")

    def test_returns_existing_user_without_duplicate_insert(self) -> None:
        first_user, _ = login_or_signup(
            self.db,
            "valid-token",
            verifier=FakeVerifier(self.profile),
        )
        second_user, is_new_user = login_or_signup(
            self.db,
            "valid-token",
            verifier=FakeVerifier(self.profile),
        )

        user_count = self.db.scalar(select(func.count()).select_from(User))
        self.assertFalse(is_new_user)
        self.assertEqual(second_user.id, first_user.id)
        self.assertEqual(user_count, 1)


if __name__ == "__main__":
    unittest.main()
