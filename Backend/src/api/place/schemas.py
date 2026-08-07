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
    radius_m: int = Field(ge=3000, le=5000)
    anchor: PlaceAnchor
    counts: NearbyPlaceCounts
    places: list[NearbyPlace]
    truncated: bool
    related_enrichment_applied: bool
