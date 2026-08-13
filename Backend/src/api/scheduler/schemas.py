from datetime import date, datetime
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
from api.scheduler.models import (
    CompanionType,
    MobilityMode,
    ScheduleRole,
    TimeSlot,
    TripType,
)


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
    scheduled_start_datetime: AwareDatetime | None = None
    scheduled_end_datetime: AwareDatetime | None = None

    @model_validator(mode="after")
    def _validate_scheduled_window(self) -> Self:
        if (self.scheduled_start_datetime is None) != (
            self.scheduled_end_datetime is None
        ):
            raise ValueError("장소 방문 시작·종료 일시는 함께 지정해야 합니다.")
        if (
            self.scheduled_start_datetime is not None
            and self.scheduled_end_datetime is not None
            and self.scheduled_end_datetime <= self.scheduled_start_datetime
        ):
            raise ValueError("장소 방문 종료 일시는 시작 일시 이후여야 합니다.")
        return self


class SchedulerPlaceUpdateRequest(BaseModel):
    day_no: int | None = Field(default=None, ge=1)
    time_slot: TimeSlot | None = None
    visit_order: int | None = Field(default=None, ge=1)
    scheduled_start_datetime: AwareDatetime | None = None
    scheduled_end_datetime: AwareDatetime | None = None

    @model_validator(mode="after")
    def _validate_update(self) -> Self:
        if not self.model_fields_set:
            raise ValueError("수정할 일정 필드를 하나 이상 지정해야 합니다.")
        if (
            self.scheduled_start_datetime is not None
            and self.scheduled_end_datetime is not None
            and self.scheduled_end_datetime <= self.scheduled_start_datetime
        ):
            raise ValueError("장소 방문 종료 일시는 시작 일시 이후여야 합니다.")
        return self


class AccommodationStayAssignment(BaseModel):
    scheduler_place_id: int = Field(
        ge=1,
        description="일정에 이미 저장된 숙소 SchedulerPlace ID",
    )
    check_in_date: date
    check_out_date: date

    @model_validator(mode="after")
    def _validate_date_range(self) -> Self:
        if self.check_out_date <= self.check_in_date:
            raise ValueError("숙박 체크아웃 날짜는 체크인 날짜 이후여야 합니다.")
        return self


class SchedulerStaysReplaceRequest(BaseModel):
    stays: list[AccommodationStayAssignment] = Field(
        ...,
        min_length=1,
        description="여행의 모든 숙소와 숙박 범위를 시간순으로 전달",
    )

    @model_validator(mode="after")
    def _validate_unique_places(self) -> Self:
        place_ids = [stay.scheduler_place_id for stay in self.stays]
        if len(place_ids) != len(set(place_ids)):
            raise ValueError("같은 숙소를 숙박 배정에 중복 지정할 수 없습니다.")
        return self


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
    places: list[SchedulerPlaceSelection] = Field(
        ...,
        min_length=1,
        max_length=31,
        description="nearby에서 선택한 장소 목록. 순서와 시간은 서버가 자동 배정",
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

        content_ids = [item.content_id for item in self.places]
        if len(content_ids) != len(set(content_ids)):
            raise ValueError("같은 장소를 한 스케줄러에 중복 선택할 수 없습니다.")
        if self.mobility_mode == MobilityMode.WALK and len(self.places) > 6:
            raise ValueError(
                "도보 일정은 카카오 API 1회 호출 기준 장소를 최대 6개까지 선택할 수 있습니다."
            )
        accommodation_count = sum(
            place.category == PlaceCategory.ACCOMMODATION for place in self.places
        )
        trip_nights = (self.end_datetime.date() - self.start_datetime.date()).days
        if accommodation_count > trip_nights:
            raise ValueError(
                "숙박 장소는 여행 박 수를 초과해 선택할 수 없습니다. "
                f"현재 일정은 {trip_nights}박이며 최대 {trip_nights}곳까지 가능합니다."
            )
        if accommodation_count and (
            self.trip_type != TripType.OVERNIGHT
            or self.start_datetime.date() == self.end_datetime.date()
        ):
            raise ValueError(
                "숙박 장소는 날짜가 다른 1박 이상 일정에서만 선택할 수 있습니다."
            )
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
    scheduled_start_datetime: datetime | None
    scheduled_end_datetime: datetime | None
    travel_seconds_from_previous: int | None
    travel_distance_m: int | None
    schedule_role: ScheduleRole
    check_in_datetime: datetime | None
    check_out_datetime: datetime | None
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
    optimization_basis: str
    route_verified: bool
    places: list[SchedulerPlaceResponse] = Field(default_factory=list)
