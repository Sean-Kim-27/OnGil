from pydantic import BaseModel, Field
from typing import Optional

# 1. 프론트에서 백엔드로 쏠 때 (Request)
class ProfileUpdateRequest(BaseModel):
    # 닉네임은 필수값이고 최소 2자, 최대 15자로 컷
    nickname: str = Field(..., min_length=2, max_length=15, description="유저 닉네임")
    profile_image_url: Optional[str] = Field(None, description="프로필 이미지 URL")

# 2. 백엔드에서 프론트로 내려줄 때 (Response)
class UserResponse(BaseModel):
    id: int
    social_provider: str
    nickname: Optional[str]
    profile_image_url: Optional[str]
    status: str

    # SQLAlchemy 모델 객체를 Pydantic으로 자동 변환해주는 개사기 옵션
    class Config:
        from_attributes = True