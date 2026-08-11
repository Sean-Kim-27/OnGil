from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, Query, status

from api.scheduler.schemas import (
    SchedulerCreateRequest,
    SchedulerPlaceCreateRequest,
    SchedulerPlaceResponse,
    SchedulerRecommendationsResponse,
    SchedulerResponse,
)
from api.scheduler.service import (
    MemoryPlaceNotFoundError,
    RecommendationService,
    SchedulerNotFoundError,
    SchedulerService,
)
from core.config import settings
from core.dependencies import CurrentUser, DatabaseSession
from infra.tour_api import (
    TourApiClient,
    TourApiConfigurationError,
    TourApiResponseError,
    TourApiUnavailableError,
)

router = APIRouter(prefix="/schedulers", tags=["schedulers"])


def get_tour_api_client() -> TourApiClient:
    try:
        return TourApiClient(
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


TourApiClientDependency = Annotated[TourApiClient, Depends(get_tour_api_client)]


@router.post(
    "",
    response_model=SchedulerResponse,
    status_code=status.HTTP_201_CREATED,
    summary="새 일정(스케줄러) 생성",
)
def create_scheduler(
    request: SchedulerCreateRequest,
    current_user: CurrentUser,
    db: DatabaseSession,
) -> SchedulerResponse:
    service = SchedulerService(db)
    try:
        scheduler = service.create(current_user.id, request)
    except MemoryPlaceNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from exc
    return SchedulerResponse.model_validate(scheduler)


@router.get("", response_model=list[SchedulerResponse], summary="내 일정 목록 조회")
def list_schedulers(
    current_user: CurrentUser, db: DatabaseSession
) -> list[SchedulerResponse]:
    service = SchedulerService(db)
    schedulers = service.list_owned(current_user.id)
    return [SchedulerResponse.model_validate(scheduler) for scheduler in schedulers]


@router.get(
    "/{scheduler_id}", response_model=SchedulerResponse, summary="일정 상세 조회"
)
def get_scheduler(
    scheduler_id: int,
    current_user: CurrentUser,
    db: DatabaseSession,
) -> SchedulerResponse:
    service = SchedulerService(db)
    try:
        scheduler = service.get_owned(current_user.id, scheduler_id)
    except SchedulerNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from exc
    return SchedulerResponse.model_validate(scheduler)


@router.delete(
    "/{scheduler_id}", status_code=status.HTTP_204_NO_CONTENT, summary="일정 삭제"
)
def delete_scheduler(
    scheduler_id: int,
    current_user: CurrentUser,
    db: DatabaseSession,
) -> None:
    service = SchedulerService(db)
    try:
        service.delete_owned(current_user.id, scheduler_id)
    except SchedulerNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from exc


@router.post(
    "/{scheduler_id}/places",
    response_model=SchedulerPlaceResponse,
    status_code=status.HTTP_201_CREATED,
    summary="일정에 장소 추가",
)
def add_scheduler_place(
    scheduler_id: int,
    request: SchedulerPlaceCreateRequest,
    current_user: CurrentUser,
    db: DatabaseSession,
) -> SchedulerPlaceResponse:
    service = SchedulerService(db)
    try:
        scheduler_place = service.add_place(current_user.id, scheduler_id, request)
    except SchedulerNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from exc
    return SchedulerPlaceResponse.model_validate(scheduler_place)


@router.delete(
    "/{scheduler_id}/places/{scheduler_place_id}",
    status_code=status.HTTP_204_NO_CONTENT,
    summary="일정에서 장소 제거",
)
def remove_scheduler_place(
    scheduler_id: int,
    scheduler_place_id: int,
    current_user: CurrentUser,
    db: DatabaseSession,
) -> None:
    service = SchedulerService(db)
    try:
        service.remove_place(current_user.id, scheduler_id, scheduler_place_id)
    except SchedulerNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from exc


@router.get(
    "/{scheduler_id}/recommendations",
    response_model=SchedulerRecommendationsResponse,
    summary="장소 연식 + 거리 가중치 기반 추천 장소 조회",
)
async def get_recommendations(
    scheduler_id: int,
    current_user: CurrentUser,
    db: DatabaseSession,
    client: TourApiClientDependency,
    limit: Annotated[int, Query(ge=1, le=50)] = 20,
) -> SchedulerRecommendationsResponse:
    service = RecommendationService(db, client)
    try:
        scheduler, memory_place, places = await service.recommend(
            current_user.id, scheduler_id, limit=limit
        )
    except SchedulerNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from exc
    except MemoryPlaceNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_400_BAD_REQUEST, detail=str(exc)
        ) from exc
    except TourApiUnavailableError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)
        ) from exc
    except TourApiResponseError as exc:
        raise HTTPException(
            status_code=status.HTTP_502_BAD_GATEWAY, detail=str(exc)
        ) from exc

    radius_m = min(max(round(scheduler.search_radius * 1000), 3000), 5000)
    return SchedulerRecommendationsResponse(
        scheduler_id=scheduler.id,
        anchor_title=memory_place.name,
        radius_m=radius_m,
        places=places,
    )