from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field

from api.place.models import PhotoType

# 사진 업로드는 JSON으로 image_url을 받는 방식(ArchivePhotoCreateRequest)에서
# 서버가 직접 파일을 받는 멀티파트 폼 방식으로 전환됨에 따라, 별도의 요청
# 스키마 없이 router에서 Form/File 파라미터를 직접 선언한다.


class ArchivePhotoResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    photo_type: PhotoType
    image_url: str
    mosaic_image_url: str | None
    taken_year: int | None
    status: str
    created_at: datetime


class GuestbookContentUpdateRequest(BaseModel):
    content: str | None = Field(
        default=None, max_length=100, description="방명록 텍스트 (최대 100자, 선택)"
    )


class GuestbookResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    place_id: int
    content: str | None
    created_at: datetime
    photos: list[ArchivePhotoResponse] = []