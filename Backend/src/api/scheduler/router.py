from typing import Annotated

from fastapi import APIRouter, Depends, HTTPException, status

from api.scheduler.schemas import (
    SchedulerCreateRequest,
    SchedulerPlaceCreateRequest,
    SchedulerPlaceResponse,
    SchedulerPlaceUpdateRequest,
    SchedulerResponse,
    SchedulerStaysReplaceRequest,
)
from api.scheduler.service import (
    MemoryPlaceNotFoundError,
    ScheduleOptimizationError,
    SchedulerNotFoundError,
    SchedulerService,
)
from core.config import settings
from core.dependencies import CurrentUser, DatabaseSession
from infra.kakao_route import KakaoRouteClient, RouteVerifier

router = APIRouter(prefix="/schedulers", tags=["schedulers"])


def get_route_verifier() -> RouteVerifier | None:
    api_key = (
        settings.KAKAO_REST_API_KEY.get_secret_value().strip()
        if settings.KAKAO_REST_API_KEY
        else ""
    )
    if not api_key:
        return None
    return KakaoRouteClient(
        rest_api_key=api_key,
        timeout_seconds=settings.KAKAO_ROUTE_TIMEOUT_SECONDS,
    )


RouteVerifierDependency = Annotated[
    RouteVerifier | None,
    Depends(get_route_verifier),
]


@router.post(
    "",
    response_model=SchedulerResponse,
    status_code=status.HTTP_201_CREATED,
    summary="기준 장소와 선택 장소를 포함한 새 일정 일괄 생성",
)
def create_scheduler(
    request: SchedulerCreateRequest,
    current_user: CurrentUser,
    db: DatabaseSession,
    route_verifier: RouteVerifierDependency,
) -> SchedulerResponse:
    service = SchedulerService(db, route_verifier)
    try:
        scheduler = service.create(current_user.id, request)
    except MemoryPlaceNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from exc
    except ScheduleOptimizationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
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


@router.put(
    "/{scheduler_id}/stays",
    response_model=SchedulerResponse,
    summary="숙박 범위·숙소 순서 전체 교체 후 일정 재최적화",
)
def replace_scheduler_stays(
    scheduler_id: int,
    request: SchedulerStaysReplaceRequest,
    current_user: CurrentUser,
    db: DatabaseSession,
    route_verifier: RouteVerifierDependency,
) -> SchedulerResponse:
    service = SchedulerService(db, route_verifier)
    try:
        scheduler = service.replace_stays(current_user.id, scheduler_id, request)
    except (SchedulerNotFoundError, MemoryPlaceNotFoundError) as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from exc
    except ScheduleOptimizationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
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
    summary="일정에 장소 추가 (/places/nearby에서 고른 장소를 그대로 전달)",
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
    except ScheduleOptimizationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
        ) from exc
    return SchedulerPlaceResponse.model_validate(scheduler_place)


@router.patch(
    "/{scheduler_id}/places/{scheduler_place_id}",
    response_model=SchedulerPlaceResponse,
    summary="자동 생성된 장소의 순서·시간 수정",
)
def update_scheduler_place(
    scheduler_id: int,
    scheduler_place_id: int,
    request: SchedulerPlaceUpdateRequest,
    current_user: CurrentUser,
    db: DatabaseSession,
) -> SchedulerPlaceResponse:
    service = SchedulerService(db)
    try:
        scheduler_place = service.update_place(
            current_user.id,
            scheduler_id,
            scheduler_place_id,
            request,
        )
    except SchedulerNotFoundError as exc:
        raise HTTPException(
            status_code=status.HTTP_404_NOT_FOUND, detail=str(exc)
        ) from exc
    except ScheduleOptimizationError as exc:
        raise HTTPException(
            status_code=status.HTTP_422_UNPROCESSABLE_CONTENT,
            detail=str(exc),
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
