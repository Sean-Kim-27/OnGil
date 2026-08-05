import os
import unittest
from unittest.mock import patch

os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("GOOGLE_CLIENT_ID", "test.apps.googleusercontent.com")
os.environ.setdefault("KAKAO_APP_ID", "1234")
os.environ.setdefault("JWT_SECRET_KEY", "test-only-secret-key-with-32-characters")

import httpx
from google.auth.exceptions import TransportError
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from api.auth.models import User
from api.auth.schemas import SocialProvider
from api.auth.service import (
    KAKAO_INTROSPECTION_URL,
    KAKAO_USERINFO_URL,
    InvalidSocialTokenError,
    SocialProfile,
    SocialProviderUnavailableError,
    SocialTokenVerifier,
    login_or_signup,
)
from core.database import Base


class FakeVerifier:
    def __init__(self, profile: SocialProfile) -> None:
        self.profile = profile

    def verify(self, provider: SocialProvider, token: str) -> SocialProfile:
        return self.profile


class SocialTokenVerifierTests(unittest.TestCase):
    def test_distinguishes_kakao_access_token(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            if str(request.url) == KAKAO_INTROSPECTION_URL:
                return httpx.Response(
                    200,
                    json={"id": 12345, "app_id": 1234, "expires_in": 3600},
                )
            if str(request.url) == KAKAO_USERINFO_URL:
                return httpx.Response(
                    200,
                    json={
                        "id": 12345,
                        "kakao_account": {
                            "email": "kakao@example.com",
                            "is_email_valid": True,
                            "is_email_verified": True,
                            "profile": {"nickname": "카카오 사용자"},
                        },
                    },
                )
            raise AssertionError(f"Unexpected URL: {request.url}")

        client = httpx.Client(transport=httpx.MockTransport(handler))
        profile = SocialTokenVerifier(client).verify(
            SocialProvider.KAKAO,
            "kakao-access-token",
        )

        self.assertEqual(profile.provider, SocialProvider.KAKAO)
        self.assertEqual(profile.social_id, "12345")
        self.assertEqual(profile.email, "kakao@example.com")

    def test_rejects_kakao_token_issued_for_another_app(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            self.assertEqual(str(request.url), KAKAO_INTROSPECTION_URL)
            return httpx.Response(
                200,
                json={"id": 12345, "app_id": 9999, "expires_in": 3600},
            )

        client = httpx.Client(transport=httpx.MockTransport(handler))
        with self.assertRaises(InvalidSocialTokenError):
            SocialTokenVerifier(client).verify(
                SocialProvider.KAKAO,
                "other-app-token",
            )

    def test_rejects_kakao_user_id_mismatch(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            if str(request.url) == KAKAO_INTROSPECTION_URL:
                return httpx.Response(
                    200,
                    json={"id": 12345, "app_id": 1234, "expires_in": 3600},
                )
            if str(request.url) == KAKAO_USERINFO_URL:
                return httpx.Response(200, json={"id": 54321})
            raise AssertionError(f"Unexpected URL: {request.url}")

        client = httpx.Client(transport=httpx.MockTransport(handler))
        with self.assertRaises(InvalidSocialTokenError):
            SocialTokenVerifier(client).verify(
                SocialProvider.KAKAO,
                "mismatched-user-token",
            )

    def test_rejects_expired_kakao_token(self) -> None:
        client = httpx.Client(
            transport=httpx.MockTransport(
                lambda request: httpx.Response(
                    200,
                    json={"id": 12345, "app_id": 1234, "expires_in": 0},
                )
            )
        )

        with self.assertRaises(InvalidSocialTokenError):
            SocialTokenVerifier(client).verify(
                SocialProvider.KAKAO,
                "expired-token",
            )

    @patch("api.auth.service.google_id_token.verify_oauth2_token")
    def test_accepts_google_id_token(self, verify_mock) -> None:
        verify_mock.return_value = {
            "sub": "google-user-1",
            "aud": "test.apps.googleusercontent.com",
            "iss": "https://accounts.google.com",
            "exp": 4_102_444_800,
            "email": "google@example.com",
            "email_verified": True,
            "name": "Google User",
        }

        profile = SocialTokenVerifier().verify(
            SocialProvider.GOOGLE, "header.payload.signature"
        )

        self.assertEqual(profile.provider, SocialProvider.GOOGLE)
        self.assertEqual(profile.social_id, "google-user-1")
        self.assertEqual(profile.email, "google@example.com")
        self.assertEqual(
            verify_mock.call_args.kwargs["audience"],
            "test.apps.googleusercontent.com",
        )

    @patch("api.auth.service.google_id_token.verify_oauth2_token")
    def test_rejects_invalid_google_id_token(self, verify_mock) -> None:
        verify_mock.side_effect = ValueError("bad signature")
        with self.assertRaises(InvalidSocialTokenError):
            SocialTokenVerifier().verify(
                SocialProvider.GOOGLE,
                "unknown-token",
            )

    @patch("api.auth.service.google_id_token.verify_oauth2_token")
    def test_rejects_wrong_google_audience_or_issuer(self, verify_mock) -> None:
        base_payload = {
            "sub": "google-user-1",
            "aud": "other-client.apps.googleusercontent.com",
            "iss": "https://accounts.google.com",
            "exp": 4_102_444_800,
        }
        verifier = SocialTokenVerifier()

        verify_mock.return_value = base_payload
        with self.assertRaises(InvalidSocialTokenError):
            verifier.verify(SocialProvider.GOOGLE, "wrong-audience")

        verify_mock.return_value = {
            **base_payload,
            "aud": "test.apps.googleusercontent.com",
            "iss": "https://attacker.example",
        }
        with self.assertRaises(InvalidSocialTokenError):
            verifier.verify(SocialProvider.GOOGLE, "wrong-issuer")

    @patch("api.auth.service.google_id_token.verify_oauth2_token")
    def test_reports_google_transport_failure(self, verify_mock) -> None:
        verify_mock.side_effect = TransportError("network unavailable")

        with self.assertRaises(SocialProviderUnavailableError):
            SocialTokenVerifier().verify(SocialProvider.GOOGLE, "valid-shape-token")


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
            SocialProvider.GOOGLE,
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
            SocialProvider.GOOGLE,
            "valid-token",
            verifier=FakeVerifier(self.profile),
        )
        second_user, is_new_user = login_or_signup(
            self.db,
            SocialProvider.GOOGLE,
            "valid-token",
            verifier=FakeVerifier(self.profile),
        )

        user_count = self.db.scalar(select(func.count()).select_from(User))
        self.assertFalse(is_new_user)
        self.assertEqual(second_user.id, first_user.id)
        self.assertEqual(user_count, 1)

    def test_rejects_provider_confusion(self) -> None:
        with self.assertRaises(InvalidSocialTokenError):
            login_or_signup(
                self.db,
                SocialProvider.KAKAO,
                "google-token-labeled-as-kakao",
                verifier=FakeVerifier(self.profile),
            )


if __name__ == "__main__":
    unittest.main()
