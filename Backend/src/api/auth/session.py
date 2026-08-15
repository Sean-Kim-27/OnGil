import hashlib
import secrets
from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from uuid import uuid4

from sqlalchemy import select, update
from sqlalchemy.exc import SQLAlchemyError
from sqlalchemy.orm import Session

from api.auth.models import RefreshSession, User
from core.config import settings
from core.security import create_access_token


class InvalidRefreshTokenError(ValueError):
    """Raised when a refresh token is missing, expired, or revoked."""


class RefreshTokenReuseError(InvalidRefreshTokenError):
    """Raised when a rotated refresh token is presented again."""


@dataclass(frozen=True)
class SessionTokenPair:
    access_token: str
    refresh_token: str
    expires_in: int


def create_session(
    db: Session,
    user: User,
    device_id: str | None = None,
) -> SessionTokenPair:
    now = datetime.now(timezone.utc)
    raw_refresh_token = _new_refresh_token()
    refresh_session = RefreshSession(
        user_id=user.id,
        token_hash=_hash_refresh_token(raw_refresh_token),
        token_family=str(uuid4()),
        device_id=device_id,
        expires_at=now + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
    )
    db.add(refresh_session)
    _commit(db)

    access_token = create_access_token(user.id)
    return SessionTokenPair(
        access_token=access_token.value,
        refresh_token=raw_refresh_token,
        expires_in=access_token.expires_in,
    )


def rotate_refresh_token(
    db: Session,
    raw_refresh_token: str,
) -> tuple[User, SessionTokenPair]:
    now = datetime.now(timezone.utc)
    token_hash = _hash_refresh_token(raw_refresh_token)
    refresh_session = db.scalar(
        select(RefreshSession)
        .where(RefreshSession.token_hash == token_hash)
        .with_for_update()
    )
    if refresh_session is None:
        raise InvalidRefreshTokenError("유효하지 않은 refresh token입니다.")

    if refresh_session.revoked_at is not None:
        _revoke_family(db, refresh_session.token_family, now, "reuse_detected")
        _commit(db)
        raise RefreshTokenReuseError("폐기된 refresh token이 재사용되었습니다.")

    if _as_utc(refresh_session.expires_at) <= now:
        refresh_session.revoked_at = now
        refresh_session.revoked_reason = "expired"
        _commit(db)
        raise InvalidRefreshTokenError("만료된 refresh token입니다.")

    user = db.get(User, refresh_session.user_id)
    if user is None:
        _revoke_family(db, refresh_session.token_family, now, "user_missing")
        _commit(db)
        raise InvalidRefreshTokenError("유효하지 않은 refresh token입니다.")

    new_raw_token = _new_refresh_token()
    new_token_hash = _hash_refresh_token(new_raw_token)
    db.add(
        RefreshSession(
            user_id=user.id,
            token_hash=new_token_hash,
            token_family=refresh_session.token_family,
            device_id=refresh_session.device_id,
            expires_at=now + timedelta(days=settings.REFRESH_TOKEN_EXPIRE_DAYS),
        )
    )
    refresh_session.revoked_at = now
    refresh_session.revoked_reason = "rotated"
    refresh_session.replaced_by_token_hash = new_token_hash
    refresh_session.last_used_at = now
    _commit(db)

    access_token = create_access_token(user.id)
    return user, SessionTokenPair(
        access_token=access_token.value,
        refresh_token=new_raw_token,
        expires_in=access_token.expires_in,
    )


def revoke_refresh_session(db: Session, raw_refresh_token: str) -> None:
    now = datetime.now(timezone.utc)
    refresh_session = db.scalar(
        select(RefreshSession).where(
            RefreshSession.token_hash == _hash_refresh_token(raw_refresh_token)
        )
    )
    if refresh_session is None:
        return

    _revoke_family(db, refresh_session.token_family, now, "logout")
    _commit(db)


def _revoke_family(
    db: Session,
    token_family: str,
    revoked_at: datetime,
    reason: str,
) -> None:
    db.execute(
        update(RefreshSession)
        .where(RefreshSession.token_family == token_family)
        .values(revoked_at=revoked_at, revoked_reason=reason)
    )


def _new_refresh_token() -> str:
    return secrets.token_urlsafe(48)


def _hash_refresh_token(token: str) -> str:
    return hashlib.sha256(token.encode("utf-8")).hexdigest()


def _as_utc(value: datetime) -> datetime:
    if value.tzinfo is None:
        return value.replace(tzinfo=timezone.utc)
    return value.astimezone(timezone.utc)


def _commit(db: Session) -> None:
    try:
        db.commit()
    except SQLAlchemyError:
        db.rollback()
        raise
