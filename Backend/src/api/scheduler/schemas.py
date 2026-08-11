from datetime import datetime
from enum import Enum
from typing import Self
from urllib.parse import urlparse, urlunparse

from pydantic import (
    AwareDatetime,
    BaseModel,
    ConfigDict,
    Field,
    field_validator,
    model_validator,
)

from api.place.schemas import PlaceCategory
from api.scheduler.models import CompanionType, MobilityMode, TimeSlot, TripType


class SearchRadiusKm(int, Enum):
    THREE_KM = 3
    FIVE_KM = 5


class MemoryPlaceSelection(BaseModel):
    """nearby 검색의 query와 anchor를 합쳐 저장할 추억의 장소."""

    name: str = Field(
        min_length=1,
        max_length=100,
        description="사용자가 nearby 검색창에 입력한 장소명",
    )
    address: str | None = Field(default=None, max_length=255)
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)


class SchedulerPlaceSelection(BaseModel):
    """/places/nearby 응답에서 사용자가 고른 장소 하나를 그대로 실어 보내는 값.

    scheduler_places.place_id는 우리 DB의 내부 PK를 참조해야 하므로,
    프론트가 TourAPI content_id를 바로 넣으면 안 됨. 백엔드가 이 값으로
    Place 테이블을 조회하고, 없으면 새로 만들어서 내부 PK를 얻는다.
    """

    content_id: str = Field(
        ...,
        min_length=1,
        max_length=100,
        description="TourAPI content_id (api_place_id)",
    )
    title: str = Field(..., min_length=1, max_length=255)
    category: PlaceCategory
    latitude: float = Field(ge=-90, le=90)
    longitude: float = Field(ge=-180, le=180)
    image_url: str | None = Field(default=None, max_length=500)
    kakao_place_id: str | None = Field(
        default=None,
        min_length=1,
        max_length=100,
        description="Kakao Local 장소 ID. 링크 확인 실패 시 null",
    )
    place_url: str | None = Field(
        default=None,
        min_length=1,
        max_length=500,
        description="Kakao Local 장소 상세 페이지 URL. 링크 확인 실패 시 null",
    )

    @field_validator("place_url")
    @classmethod
    def _validate_kakao_place_url(cls, value: str | None) -> str | None:
        if value is None:
            return None
        parsed = urlparse(value.strip())
        if (
            parsed.scheme not in {"http", "https"}
            or parsed.hostname != "place.map.kakao.com"
        ):
            raise ValueError("place_url은 카카오맵 장소 상세 URL이어야 합니다.")
        return urlunparse(parsed._replace(scheme="https"))

    @model_validator(mode="after")
    def _validate_kakao_link_pair(self) -> Self:
        if (self.kakao_place_id is None) != (self.place_url is None):
            raise ValueError(
                "kakao_place_id와 place_url은 함께 지정하거나 모두 null이어야 합니다."
            )
        return self


class SchedulerPlaceCreateRequest(BaseModel):
    place: SchedulerPlaceSelection
    day_no: int = Field(default=1, ge=1, description="몇 일차인지")
    time_slot: TimeSlot | None = None
    visit_order: int = Field(..., ge=1, description="해당 일차의 방문 순서")


class SchedulerCreateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=100)
    mobility_mode: MobilityMode
    search_radius: SearchRadiusKm = Field(description="탐색 반경: 3km 또는 5km")
    trip_type: TripType
    memory_place_id: int | None = Field(
        default=None,
        ge=1,
        description="기존 추억의 장소를 재사용할 때 지정",
    )
    memory_place: MemoryPlaceSelection | None = Field(
        default=None,
        description="nearby 검색의 query와 anchor로 새로 저장할 추억의 장소",
    )
    places: list[SchedulerPlaceCreateRequest] = Field(
        ...,
        min_length=1,
        description="nearby에서 선택하고 Kakao URL 확인을 시도한 장소 목록",
    )
    companion_type: CompanionType
    companion_count: int = Field(default=1, ge=1, le=20)
    start_datetime: AwareDatetime
    end_datetime: AwareDatetime

    @model_validator(mode="after")
    def _validate_scheduler(self) -> Self:
        if self.end_datetime <= self.start_datetime:
            raise ValueError("end_datetime은 start_datetime 이후여야 합니다.")
        if (self.memory_place_id is None) == (self.memory_place is None):
            raise ValueError(
                "memory_place_id와 memory_place 중 정확히 하나를 지정해야 합니다."
            )

        content_ids = [item.place.content_id for item in self.places]
        if len(content_ids) != len(set(content_ids)):
            raise ValueError("같은 장소를 한 스케줄러에 중복 선택할 수 없습니다.")

        visit_positions = [(item.day_no, item.visit_order) for item in self.places]
        if len(visit_positions) != len(set(visit_positions)):
            raise ValueError("같은 일차에 동일한 방문 순서를 지정할 수 없습니다.")
        return self


class MemoryPlaceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    name: str
    address: str
    latitude: float = Field(validation_alias="lat")
    longitude: float = Field(validation_alias="lng")


class StoredPlaceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    content_id: str = Field(validation_alias="api_place_id")
    title: str = Field(validation_alias="name")
    category: PlaceCategory
    latitude: float = Field(validation_alias="lat")
    longitude: float = Field(validation_alias="lng")
    image_url: str | None
    kakao_place_id: str | None
    place_url: str | None = Field(validation_alias="kakao_place_url")


class SchedulerPlaceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    place_id: int
    day_no: int
    time_slot: TimeSlot | None
    visit_order: int
    place: StoredPlaceResponse


class SchedulerResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    mobility_mode: MobilityMode
    search_radius: SearchRadiusKm
    trip_type: TripType
    memory_place_id: int | None
    memory_place: MemoryPlaceResponse | None
    companion_type: CompanionType
    companion_count: int
    start_datetime: datetime
    end_datetime: datetime
    places: list[SchedulerPlaceResponse] = Field(default_factory=list)
