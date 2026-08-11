from fastapi import APIRouter, HTTPException, status

from api.scheduler.schemas import (
    SchedulerCreateRequest,
    SchedulerPlaceCreateRequest,
    SchedulerPlaceResponse,
    SchedulerResponse,
)
from api.scheduler.service import (
    MemoryPlaceNotFoundError,
    SchedulerNotFoundError,
    SchedulerService,
)
from core.dependencies import CurrentUser, DatabaseSession

router = APIRouter(prefix="/schedulers", tags=["schedulers"])


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