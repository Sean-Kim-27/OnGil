from datetime import datetime

from pydantic import BaseModel, ConfigDict, Field, field_validator

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


class SchedulerPlaceCreateRequest(BaseModel):
    place_id: int
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


class RecommendedPlace(BaseModel):
    content_id: str
    title: str
    category: str
    address: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    distance_m: int = Field(ge=0)
    registered_year: int | None = Field(
        default=None, description="TourAPI 등록 연도 기준 추정 연식"
    )
    distance_score: float = Field(ge=0, le=1)
    age_score: float = Field(ge=0, le=1)
    total_score: float = Field(ge=0, le=1)
    image_url: str | None = None


class SchedulerRecommendationsResponse(BaseModel):
    scheduler_id: int
    anchor_title: str
    radius_m: int = Field(ge=3000, le=5000)
    places: list[RecommendedPlace]