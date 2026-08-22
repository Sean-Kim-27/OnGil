import os
import unittest

os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("GOOGLE_CLIENT_ID", "test.apps.googleusercontent.com")
os.environ.setdefault("KAKAO_APP_ID", "1234")
os.environ.setdefault("JWT_SECRET_KEY", "test-only-secret-key-with-32-characters")

from pydantic import SecretStr

from core.config import Settings


class SettingsTests(unittest.TestCase):
    def test_kakao_rest_api_key_is_loaded_as_secret(self) -> None:
        settings = Settings(
            _env_file=None,
            DATABASE_URL="sqlite://",
            GOOGLE_CLIENT_ID="test.apps.googleusercontent.com",
            KAKAO_APP_ID=1234,
            KAKAO_REST_API_KEY="kakao-rest-key",
            JWT_SECRET_KEY="test-only-secret-key-with-32-characters",
        )

        self.assertIsInstance(settings.KAKAO_REST_API_KEY, SecretStr)
        self.assertEqual(
            settings.KAKAO_REST_API_KEY.get_secret_value(),
            "kakao-rest-key",
        )


if __name__ == "__main__":
    unittest.main()
