from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status

from api.place.schemas import (
    KakaoPlaceLinkRequest,
    KakaoPlaceLinkResponse,
    NearbyPlacesResponse,
    SearchRadiusMeters,
)
from api.place.service import (
    KakaoPlaceLinkNotFoundError,
    KakaoPlaceLinkService,
    NearbyPlaceService,
    PlaceNotFoundError,
)
from core.config import settings
from core.dependencies import CurrentUser
from infra.kakao_local import KakaoLocalClient, KakaoLocalError
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
    kakao_rest_api_key = (
        settings.KAKAO_REST_API_KEY.get_secret_value().strip()
        if settings.KAKAO_REST_API_KEY
        else ""
    )
    kakao_anchor_client = None
    if kakao_rest_api_key:
        kakao_anchor_client = KakaoLocalClient(
            rest_api_key=kakao_rest_api_key,
            timeout_seconds=settings.TOUR_API_TIMEOUT_SECONDS,
        )
    return NearbyPlaceService(client, kakao_anchor_client)


NearbyPlaceServiceDependency = Annotated[
    NearbyPlaceService,
    Depends(get_nearby_place_service),
]


def get_kakao_place_link_service() -> KakaoPlaceLinkService:
    kakao_rest_api_key = (
        settings.KAKAO_REST_API_KEY.get_secret_value().strip()
        if settings.KAKAO_REST_API_KEY
        else ""
    )
    if not kakao_rest_api_key:
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="카카오 장소 검색 API가 구성되지 않았습니다.",
        )
    return KakaoPlaceLinkService(
        KakaoLocalClient(
            rest_api_key=kakao_rest_api_key,
            timeout_seconds=settings.TOUR_API_TIMEOUT_SECONDS,
        )
    )


KakaoPlaceLinkServiceDependency = Annotated[
    KakaoPlaceLinkService,
    Depends(get_kakao_place_link_service),
]


@router.get(
    "/nearby",
    response_model=NearbyPlacesResponse,
    summary="입력한 장소 주변의 관광·문화·숙박·음식 장소 통합 조회",
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
            description="기준 장소명(학교·아파트·관광지 등)",
        ),
    ],
    radius_m: Annotated[
        SearchRadiusMeters,
        Query(description="검색 반경(미터): 3km 또는 5km"),
    ] = 5000,
) -> NearbyPlacesResponse:
    del current_user  # Authentication is required to protect the public-data quota.
    try:
        return await service.search(query=query.strip(), radius_m=int(radius_m))
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


@router.post(
    "/kakao-links/resolve",
    response_model=KakaoPlaceLinkResponse,
    summary="선택한 장소의 카카오맵 상세 페이지 링크 조회",
)
async def resolve_kakao_place_link(
    request: KakaoPlaceLinkRequest,
    current_user: CurrentUser,
    service: KakaoPlaceLinkServiceDependency,
) -> KakaoPlaceLinkResponse:
    del current_user  # Authentication is required to protect the Kakao API quota.
    try:
        return await service.resolve(
            title=request.title.strip(),
            latitude=request.latitude,
            longitude=request.longitude,
        )
    except KakaoPlaceLinkNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND,
            detail=str(exc),
        ) from exc
    except KakaoLocalError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY,
            detail=str(exc),
        ) from exc
