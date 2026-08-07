from enum import Enum

from pydantic import BaseModel, Field


class PlaceCategory(str, Enum):
    RESTAURANT = "restaurant"
    CAFE = "cafe"
    TOURIST_ATTRACTION = "tourist_attraction"


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
    classification_code: str | None = None
    related_rank: int | None = Field(default=None, ge=1)
    related_category: str | None = None


class NearbyPlaceCounts(BaseModel):
    restaurant: int = Field(ge=0)
    cafe: int = Field(ge=0)
    tourist_attraction: int = Field(ge=0)
    total: int = Field(ge=0)


class NearbyPlacesResponse(BaseModel):
    query: str
    radius_m: int = Field(ge=3000, le=5000)
    anchor: PlaceAnchor
    counts: NearbyPlaceCounts
    places: list[NearbyPlace]
    truncated: bool
    related_enrichment_applied: bool
