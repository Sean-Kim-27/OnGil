from datetime import datetime
from enum import Enum
from typing import Self

from pydantic import AwareDatetime, BaseModel, ConfigDict, Field, model_validator

from api.place.schemas import PlaceCategory
from api.scheduler.models import CompanionType, MobilityMode, TimeSlot, TripType


class SearchRadiusKm(int, Enum):
    THREE_KM = 3
    FIVE_KM = 5


class SchedulerCreateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=100)
    mobility_mode: MobilityMode
    search_radius: SearchRadiusKm = Field(description="탐색 반경: 3km 또는 5km")
    trip_type: TripType
    memory_place_id: int | None = Field(
        default=None, description="중심이 되는 추억의 장소 id"
    )
    companion_type: CompanionType
    companion_count: int = Field(default=1, ge=1, le=20)
    start_datetime: AwareDatetime
    end_datetime: AwareDatetime

    @model_validator(mode="after")
    def _end_after_start(self) -> Self:
        if self.end_datetime <= self.start_datetime:
            raise ValueError("end_datetime은 start_datetime 이후여야 합니다.")
        return self


class SchedulerPlaceSelection(BaseModel):
    """/places/nearby 응답에서 사용자가 고른 장소 하나를 그대로 실어 보내는 값.

    scheduler_places.place_id는 우리 DB의 내부 PK를 참조해야 하므로,
    프론트가 TourAPI content_id를 바로 넣으면 안 됨. 백엔드가 이 값으로
    Place 테이블을 조회하고, 없으면 새로 만들어서 내부 PK를 얻는다.
    """

    content_id: str = Field(..., description="TourAPI content_id (api_place_id)")
    title: str
    category: PlaceCategory
    latitude: float
    longitude: float
    image_url: str | None = None


class SchedulerPlaceCreateRequest(BaseModel):
    place: SchedulerPlaceSelection
    day_no: int = Field(default=1, ge=1, description="몇 일차인지")
    time_slot: TimeSlot | None = None
    visit_order: int = Field(..., ge=1, description="해당 일차의 방문 순서")


class SchedulerPlaceResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    place_id: int
    day_no: int
    time_slot: TimeSlot | None
    visit_order: int


class SchedulerResponse(BaseModel):
    model_config = ConfigDict(from_attributes=True)

    id: int
    title: str
    mobility_mode: MobilityMode
    search_radius: float
    trip_type: TripType
    memory_place_id: int | None
    companion_type: CompanionType
    companion_count: int
    start_datetime: datetime
    end_datetime: datetime
    places: list[SchedulerPlaceResponse] = []
