from dataclasses import dataclass
from datetime import datetime, timedelta, timezone
from uuid import uuid4

import jwt
from jwt import InvalidTokenError

from core.config import settings


class InvalidAccessTokenError(ValueError):
    """Raised when an OnGil access token cannot be trusted."""


@dataclass(frozen=True)
class AccessToken:
    value: str
    expires_in: int


def create_access_token(user_id: int) -> AccessToken:
    now = datetime.now(timezone.utc)
    expires_in = settings.ACCESS_TOKEN_EXPIRE_MINUTES * 60
    payload = {
        "sub": str(user_id),
        "type": "access",
        "iss": settings.JWT_ISSUER,
        "iat": now,
        "exp": now + timedelta(seconds=expires_in),
        "jti": str(uuid4()),
    }
    token = jwt.encode(
        payload,
        settings.JWT_SECRET_KEY.get_secret_value(),
        algorithm=settings.JWT_ALGORITHM,
    )
    return AccessToken(value=token, expires_in=expires_in)


def decode_access_token(token: str) -> int:
    try:
        payload = jwt.decode(
            token,
            settings.JWT_SECRET_KEY.get_secret_value(),
            algorithms=[settings.JWT_ALGORITHM],
            issuer=settings.JWT_ISSUER,
            options={"require": ["sub", "type", "iss", "iat", "exp", "jti"]},
        )
    except InvalidTokenError as exc:
        raise InvalidAccessTokenError(
            "유효하지 않은 OnGil access token입니다."
        ) from exc

    if payload.get("type") != "access":
        raise InvalidAccessTokenError("유효하지 않은 OnGil access token입니다.")

    subject = payload.get("sub")
    try:
        user_id = int(subject)
    except (TypeError, ValueError) as exc:
        raise InvalidAccessTokenError(
            "유효하지 않은 OnGil access token입니다."
        ) from exc

    if user_id <= 0:
        raise InvalidAccessTokenError("유효하지 않은 OnGil access token입니다.")
    return user_id
