from fastapi import APIRouter, Depends, HTTPException, status
from sqlalchemy.orm import Session

from api.auth.schemas import SocialLoginRequest, SocialLoginResponse
from api.auth.service import (
    InvalidSocialTokenError,
    SocialProviderUnavailableError,
    login_or_signup,
)
from core.dependencies import get_db

router = APIRouter(prefix="/auth", tags=["auth"])


@router.post("/social-login", response_model=SocialLoginResponse)
def social_login(
    request: SocialLoginRequest,
    db: Session = Depends(get_db),
) -> SocialLoginResponse:
    """Log in an existing social user or register a new pending user."""
    try:
        user, is_new_user = login_or_signup(
            db=db,
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

    return SocialLoginResponse(
        provider=user.social_provider,
        is_new_user=is_new_user,
        user=user,
    )
