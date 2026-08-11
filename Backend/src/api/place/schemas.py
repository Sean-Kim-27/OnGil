from enum import Enum

from pydantic import BaseModel, Field


class PlaceCategory(str, Enum):
    RESTAURANT = "restaurant"
    CAFE = "cafe"
    TOURIST_ATTRACTION = "tourist_attraction"
    CULTURAL_FACILITY = "cultural_facility"
    FESTIVAL = "festival"
    TRAVEL_COURSE = "travel_course"
    LEISURE_SPORTS = "leisure_sports"
    ACCOMMODATION = "accommodation"
    SHOPPING = "shopping"
    OTHER = "other"


class SearchRadiusMeters(int, Enum):
    THREE_KM = 3000
    FIVE_KM = 5000


class PlaceAnchor(BaseModel):
    content_id: str | None = None
    title: str
    address: str | None = None
    address_detail: str | None = None
    latitude: float
    longitude: float


class NearbyPlace(BaseModel):
    content_id: str
    title: str
    category: PlaceCategory
    address: str | None = None
    address_detail: str | None = None
    latitude: float | None = None
    longitude: float | None = None
    distance_m: int = Field(ge=0)
    image_url: str | None = None
    thumbnail_url: str | None = None
    telephone: str | None = None
    content_type_id: int | None = None
    classification_code: str | None = None
    related_rank: int | None = Field(default=None, ge=1)
    related_category: str | None = None
    registered_year: int | None = Field(
        default=None, description="TourAPI 등록 연도 기준 추정 연식"
    )
    distance_score: float = Field(default=0.0, ge=0, le=1)
    age_score: float = Field(
        default=0.0, ge=0, le=1, description="음식점/관광지에만 적용. 카페는 항상 0"
    )
    total_score: float = Field(
        default=0.0,
        ge=0,
        le=1,
        description="음식점/관광지=거리+연식 가중합, 카페=거리 점수만",
    )


class NearbyPlaceCounts(BaseModel):
    restaurant: int = Field(default=0, ge=0)
    cafe: int = Field(default=0, ge=0)
    tourist_attraction: int = Field(default=0, ge=0)
    cultural_facility: int = Field(default=0, ge=0)
    festival: int = Field(default=0, ge=0)
    travel_course: int = Field(default=0, ge=0)
    leisure_sports: int = Field(default=0, ge=0)
    accommodation: int = Field(default=0, ge=0)
    shopping: int = Field(default=0, ge=0)
    other: int = Field(default=0, ge=0)
    total: int = Field(default=0, ge=0)


class NearbyPlacesResponse(BaseModel):
    query: str
    radius_m: SearchRadiusMeters
    anchor: PlaceAnchor
    counts: NearbyPlaceCounts
    places: list[NearbyPlace]
    truncated: bool
    related_enrichment_applied: bool


class KakaoPlaceLinkRequest(BaseModel):
    title: str = Field(
        min_length=1,
        max_length=100,
        pattern=r".*\S.*",
        description="nearby 결과의 장소명",
    )
    latitude: float = Field(ge=-90, le=90, description="WGS84 위도")
    longitude: float = Field(ge=-180, le=180, description="WGS84 경도")


class KakaoPlaceLinkResponse(BaseModel):
    kakao_place_id: str
    place_url: str
