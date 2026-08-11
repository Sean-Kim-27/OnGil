from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

from api.place.schemas import PlaceCategory
from api.scheduler.models import CompanionType, MobilityMode, TimeSlot, TripType


class SchedulerCreateRequest(BaseModel):
    title: str = Field(..., min_length=1, max_length=100)
    mobility_mode: MobilityMode
    search_radius: float = Field(..., gt=0, le=5, description="탐색 반경 (단위: km)")
    trip_type: TripType
    memory_place_id: int | None = Field(
        default=None, description="중심이 되는 추억의 장소 id"
    )
    companion_type: CompanionType
    companion_count: int = Field(default=1, ge=1, le=20)
    start_datetime: datetime
    end_datetime: datetime

    @field_validator("end_datetime")
    @classmethod
    def _end_after_start(cls, end_datetime: datetime, info):
        start_datetime = info.data.get("start_datetime")
        if start_datetime is not None and end_datetime <= start_datetime:
            raise ValueError("end_datetime은 start_datetime 이후여야 합니다.")
        return end_datetime


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