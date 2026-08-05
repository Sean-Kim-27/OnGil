import os
import unittest
from types import SimpleNamespace
from unittest.mock import patch

os.environ.setdefault("DATABASE_URL", "sqlite://")

from fastapi.testclient import TestClient

from api.auth.service import InvalidSocialTokenError
from main import app


class SocialLoginRouterTests(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(app)

    def tearDown(self) -> None:
        self.client.close()

    @patch("api.auth.router.login_or_signup")
    def test_returns_social_login_result(self, login_or_signup_mock) -> None:
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

        response = self.client.post(
            "/api/v1/auth/social-login",
            json={"token": "google-token"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["provider"], "GOOGLE")
        self.assertTrue(response.json()["is_new_user"])

    @patch("api.auth.router.login_or_signup")
    def test_returns_unauthorized_for_invalid_token(self, login_or_signup_mock) -> None:
        login_or_signup_mock.side_effect = InvalidSocialTokenError("invalid token")

        response = self.client.post(
            "/api/v1/auth/social-login",
            json={"token": "invalid-token"},
        )

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.json()["detail"], "invalid token")


if __name__ == "__main__":
    unittest.main()
