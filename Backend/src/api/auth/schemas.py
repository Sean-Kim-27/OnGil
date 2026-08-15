from enum import Enum

from pydantic import BaseModel, ConfigDict, Field, SecretStr


class SocialProvider(str, Enum):
    GOOGLE = "google"
    KAKAO = "kakao"


class SocialLoginRequest(BaseModel):
    provider: SocialProvider
    token: SecretStr = Field(
        ...,
        min_length=1,
        max_length=8192,
        description="Google ID token 또는 Kakao access token",
    )
    device_id: str | None = Field(None, min_length=1, max_length=255)


class ProfileUpdateRequest(BaseModel):
    nickname: str = Field(..., min_length=2, max_length=15, description="유저 닉네임")
    profile_image_url: str | None = Field(None, description="프로필 이미지 URL")


class UserResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    social_provider: SocialProvider
    email: str | None
    nickname: str | None
    profile_image_url: str | None
    status: str


class SocialLoginResponse(BaseModel):
    provider: SocialProvider
    is_new_user: bool
    user: UserResponse
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int


class RefreshTokenRequest(BaseModel):
    refresh_token: SecretStr = Field(..., min_length=32, max_length=512)


class RefreshTokenResponse(BaseModel):
    access_token: str
    refresh_token: str
    token_type: str = "bearer"
    expires_in: int
    user: UserResponse


class LogoutRequest(BaseModel):
    refresh_token: SecretStr = Field(..., min_length=32, max_length=512)
