from fastapi import APIRouter, HTTPException, Request, Response, status

from api.auth.models import User
from api.auth.schemas import (
    LogoutRequest,
    RefreshTokenRequest,
    RefreshTokenResponse,
    SocialLoginRequest,
    SocialLoginResponse,
    UserResponse,
)
from api.auth.service import (
    InvalidSocialTokenError,
    SocialProviderUnavailableError,
    login_or_signup,
)
from api.auth.session import (
    InvalidRefreshTokenError,
    create_session,
    revoke_refresh_session,
    rotate_refresh_token,
)
from core.dependencies import CurrentUser, DatabaseSession
from core.rate_limit import enforce_auth_rate_limit

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/social-login", response_model=SocialLoginResponse)
def social_login(
    request: SocialLoginRequest,
    http_request: Request,
    db: DatabaseSession,
) -> SocialLoginResponse:
    """Log in an existing social user or register a new pending user."""
    enforce_auth_rate_limit(http_request, "social-login")
    try:
        user, is_new_user = login_or_signup(
            db=db,
            provider=request.provider,
            token=request.token.get_secret_value(),
        )
    except InvalidSocialTokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail=str(exc),
        ) from exc
    except SocialProviderUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from exc

    session_tokens = create_session(db, user, request.device_id)
    return SocialLoginResponse(
        provider=user.social_provider,
        is_new_user=is_new_user,
        user=user,
        access_token=session_tokens.access_token,
        refresh_token=session_tokens.refresh_token,
        expires_in=session_tokens.expires_in,
    )


@router.post("/refresh", response_model=RefreshTokenResponse)
def refresh_session(
    request: RefreshTokenRequest,
    http_request: Request,
    db: DatabaseSession,
) -> RefreshTokenResponse:
    enforce_auth_rate_limit(http_request, "refresh")
    try:
        user, session_tokens = rotate_refresh_token(
            db,
            request.refresh_token.get_secret_value(),
        )
    except InvalidRefreshTokenError as exc:
        raise HTTPException(
            status_code=status.HTTP_401_UNAUTHORIZED,
            detail="유효하지 않은 refresh token입니다.",
        ) from exc

    return RefreshTokenResponse(
        access_token=session_tokens.access_token,
        refresh_token=session_tokens.refresh_token,
        expires_in=session_tokens.expires_in,
        user=user,
    )


@router.post("/logout", status_code=status.HTTP_204_NO_CONTENT)
def logout(
    request: LogoutRequest,
    http_request: Request,
    db: DatabaseSession,
) -> Response:
    enforce_auth_rate_limit(http_request, "logout")
    revoke_refresh_session(db, request.refresh_token.get_secret_value())
    return Response(status_code=status.HTTP_204_NO_CONTENT)


@router.get("/me", response_model=UserResponse)
def me(current_user: CurrentUser) -> User:
    return current_user
