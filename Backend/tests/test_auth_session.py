import os
import unittest
from datetime import datetime, timedelta, timezone

os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("GOOGLE_CLIENT_ID", "test.apps.googleusercontent.com")
os.environ.setdefault("KAKAO_APP_ID", "1234")
os.environ.setdefault("JWT_SECRET_KEY", "test-only-secret-key-with-32-characters")

from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from api.auth.models import RefreshSession, User
from api.auth.session import (
    InvalidRefreshTokenError,
    RefreshTokenReuseError,
    create_session,
    revoke_refresh_session,
    rotate_refresh_token,
)
from core.database import Base
from core.security import InvalidAccessTokenError, decode_access_token


class AuthSessionTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(
            self.engine,
            tables=[User.__table__, RefreshSession.__table__],
        )
        self.db = Session(self.engine)
        self.user = User(
            social_provider="google",
            social_id="google-user-1",
            email="user@example.com",
            status="ACTIVE",
        )
        self.db.add(self.user)
        self.db.commit()
        self.db.refresh(self.user)

    def tearDown(self) -> None:
        self.db.close()
        self.engine.dispose()

    def test_creates_access_and_hashed_refresh_session(self) -> None:
        tokens = create_session(self.db, self.user, "device-1")

        refresh_session = self.db.scalar(select(RefreshSession))
        self.assertEqual(decode_access_token(tokens.access_token), self.user.id)
        self.assertNotEqual(refresh_session.token_hash, tokens.refresh_token)
        self.assertEqual(len(refresh_session.token_hash), 64)
        self.assertEqual(refresh_session.device_id, "device-1")

    def test_rotates_refresh_token_and_rejects_reuse(self) -> None:
        first_tokens = create_session(self.db, self.user)
        user, second_tokens = rotate_refresh_token(
            self.db,
            first_tokens.refresh_token,
        )

        self.assertEqual(user.id, self.user.id)
        self.assertNotEqual(first_tokens.refresh_token, second_tokens.refresh_token)
        self.assertEqual(decode_access_token(second_tokens.access_token), self.user.id)

        with self.assertRaises(RefreshTokenReuseError):
            rotate_refresh_token(self.db, first_tokens.refresh_token)

        sessions = self.db.scalars(select(RefreshSession)).all()
        self.assertTrue(all(session.revoked_at is not None for session in sessions))
        self.assertTrue(
            all(session.revoked_reason == "reuse_detected" for session in sessions)
        )

    def test_logout_revokes_token_family(self) -> None:
        tokens = create_session(self.db, self.user)

        revoke_refresh_session(self.db, tokens.refresh_token)

        refresh_session = self.db.scalar(select(RefreshSession))
        self.assertIsNotNone(refresh_session.revoked_at)
        self.assertEqual(refresh_session.revoked_reason, "logout")

    def test_rejects_tampered_access_token(self) -> None:
        tokens = create_session(self.db, self.user)
        header, payload, _ = tokens.access_token.split(".")
        tampered = f"{header}.{payload}.invalid-signature"

        with self.assertRaises(InvalidAccessTokenError):
            decode_access_token(tampered)

    def test_rejects_expired_refresh_token(self) -> None:
        tokens = create_session(self.db, self.user)
        refresh_session = self.db.scalar(select(RefreshSession))
        refresh_session.expires_at = datetime.now(timezone.utc) - timedelta(seconds=1)
        self.db.commit()

        with self.assertRaises(InvalidRefreshTokenError):
            rotate_refresh_token(self.db, tokens.refresh_token)

        self.db.refresh(refresh_session)
        self.assertEqual(refresh_session.revoked_reason, "expired")


if __name__ == "__main__":
    unittest.main()
