from typing import Annotated

from api.place.schemas import NearbyPlacesResponse
from api.place.service import NearbyPlaceService, PlaceNotFoundError
from core.config import settings
from core.dependencies import CurrentUser
from fastapi import APIRouter, Depends, HTTPException, Query, status
from infra.tour_api import (
    TourApiClient,
    TourApiConfigurationError,
    TourApiResponseError,
    TourApiUnavailableError,
)

router = APIRouter(prefix="/places", tags=["places"])


def get_nearby_place_service() -> NearbyPlaceService:
    try:
        client = TourApiClient(
            service_base_url=settings.KOR_SERVICE_BASE_URL,
            relate_base_url=settings.KOR_RELATE_BASE_URL,
            service_key=(
                settings.KOR_DATA_API_KEY.get_secret_value()
                if settings.KOR_DATA_API_KEY
                else None
            ),
            timeout_seconds=settings.TOUR_API_TIMEOUT_SECONDS,
            page_size=settings.TOUR_API_PAGE_SIZE,
            max_results=settings.TOUR_API_MAX_RESULTS_PER_CATEGORY,
        )
    except TourApiConfigurationError as exc:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail=str(exc),
        ) from exc
    return NearbyPlaceService(client)


NearbyPlaceServiceDependency = Annotated[
    NearbyPlaceService,
    Depends(get_nearby_place_service),
]


@router.get(
    "/nearby",
    response_model=NearbyPlacesResponse,
    summary="입력한 장소 주변의 음식점·카페·관광지 조회",
)
async def get_nearby_places(
    current_user: CurrentUser,
    service: NearbyPlaceServiceDependency,
    query: Annotated[
        str,
        Query(
            min_length=1,
            max_length=100,
            pattern=r".*\S.*",
            description="기준 장소명",
        ),
    ],
    radius_m: Annotated[
        int,
        Query(ge=3000, le=5000, description="검색 반경(미터)"),
    ] = 5000,
) -> NearbyPlacesResponse:
    del current_user  # Authentication is required to protect the public-data quota.
    try:
        return await service.search(query=query.strip(), radius_m=radius_m)
    except PlaceNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from exc
    except TourApiUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from exc
    except TourApiResponseError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from exc
