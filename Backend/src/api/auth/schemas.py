from enum import Enum
from typing import Optional

from pydantic import BaseModel, ConfigDict, Field, SecretStr


class SocialProvider(str, Enum):
    GOOGLE = "GOOGLE"
    KAKAO = "KAKAO"


class SocialLoginRequest(BaseModel):
    token: SecretStr = Field(
        ...,
        min_length=1,
        description="Google ID/access token 또는 Kakao access token",
    )


class ProfileUpdateRequest(BaseModel):
    nickname: str = Field(..., min_length=2, max_length=15, description="유저 닉네임")
    profile_image_url: Optional[str] = Field(None, description="프로필 이미지 URL")


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    social_provider: SocialProvider
    email: Optional[str]
    nickname: Optional[str]
    profile_image_url: Optional[str]
    status: str


class SocialLoginResponse(BaseModel):
    provider: SocialProvider
    is_new_user: bool
    user: UserResponse
