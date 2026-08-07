import os
import unittest
from types import SimpleNamespace
from unittest.mock import patch

os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("GOOGLE_CLIENT_ID", "test.apps.googleusercontent.com")
os.environ.setdefault("KAKAO_APP_ID", "1234")
os.environ.setdefault("JWT_SECRET_KEY", "test-only-secret-key-with-32-characters")
os.environ["ENVIRONMENT"] = "test"
os.environ["REDIS_URL"] = ""

from fastapi.testclient import TestClient

from api.auth.service import InvalidSocialTokenError
from api.auth.session import SessionTokenPair
from core.config import settings
from core.dependencies import get_current_user
from core.rate_limit import auth_rate_limiter
from main import app


class SocialLoginRouterTests(unittest.TestCase):
    def setUp(self) -> None:
        auth_rate_limiter.reset_for_tests()
        self.client = TestClient(app)

    def tearDown(self) -> None:
        self.client.close()

    @patch("api.auth.router.create_session")
    @patch("api.auth.router.login_or_signup")
    def test_returns_social_login_result(
        self,
        login_or_signup_mock,
        create_session_mock,
    ) -> None:
        login_or_signup_mock.return_value = (
            SimpleNamespace(
                id=1,
                social_provider="GOOGLE",
                email="user@example.com",
                nickname="User",
                profile_image_url=None,
                status="PENDING",
            ),
            True,
        )
        create_session_mock.return_value = SessionTokenPair(
            access_token="ongil-access-token",
            refresh_token="ongil-refresh-token",
            expires_in=900,
        )

        response = self.client.post(
            "/api/v1/auth/social-login",
            json={"provider": "GOOGLE", "token": "google-token"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["provider"], "GOOGLE")
        self.assertTrue(response.json()["is_new_user"])
        self.assertEqual(response.json()["access_token"], "ongil-access-token")
        self.assertEqual(response.json()["refresh_token"], "ongil-refresh-token")

    @patch("api.auth.router.login_or_signup")
    def test_returns_unauthorized_for_invalid_token(self, login_or_signup_mock) -> None:
        login_or_signup_mock.side_effect = InvalidSocialTokenError("invalid token")

        response = self.client.post(
            "/api/v1/auth/social-login",
            json={"provider": "GOOGLE", "token": "invalid-token"},
        )

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()["detail"], "invalid token")

    def test_requires_explicit_provider(self) -> None:
        response = self.client.post(
            "/api/v1/auth/social-login",
            json={"token": "token-without-provider"},
        )

        self.assertEqual(response.status_code, 422)

    def test_rejects_oversized_request_body(self) -> None:
        response = self.client.post(
            "/api/v1/auth/social-login",
            content=b"x" * (settings.MAX_REQUEST_BODY_BYTES + 1),
            headers={"Content-Type": "application/json"},
        )

        self.assertEqual(response.status_code, 413)

    @patch("api.auth.router.create_session")
    @patch("api.auth.router.login_or_signup")
    def test_rate_limits_auth_requests(
        self,
        login_or_signup_mock,
        create_session_mock,
    ) -> None:
        login_or_signup_mock.return_value = (
            SimpleNamespace(
                id=1,
                social_provider="GOOGLE",
                email=None,
                nickname=None,
                profile_image_url=None,
                status="PENDING",
            ),
            False,
        )
        create_session_mock.return_value = SessionTokenPair("a", "r", 900)
        original_limit = settings.SOCIAL_LOGIN_RATE_LIMIT
        settings.SOCIAL_LOGIN_RATE_LIMIT = 2
        try:
            for _ in range(2):
                response = self.client.post(
                    "/api/v1/auth/social-login",
                    json={"provider": "GOOGLE", "token": "token"},
                )
                self.assertEqual(response.status_code, 200)

            response = self.client.post(
                "/api/v1/auth/social-login",
                json={"provider": "GOOGLE", "token": "token"},
            )
        finally:
            settings.SOCIAL_LOGIN_RATE_LIMIT = original_limit

        self.assertEqual(response.status_code, 429)
        self.assertIn("Retry-After", response.headers)

    def test_me_requires_ongil_bearer_token(self) -> None:
        response = self.client.get("/api/v1/auth/me")

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.headers["WWW-Authenticate"], "Bearer")

    def test_me_returns_authenticated_user(self) -> None:
        app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(
            id=1,
            social_provider="GOOGLE",
            email="user@example.com",
            nickname="User",
            profile_image_url=None,
            status="ACTIVE",
        )
        try:
            response = self.client.get(
                "/api/v1/auth/me",
                headers={"Authorization": "Bearer ongil-access-token"},
            )
        finally:
            app.dependency_overrides.pop(get_current_user, None)

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["id"], 1)
        self.assertEqual(response.headers["Cache-Control"], "no-store")


if __name__ == "__main__":
    unittest.main()
