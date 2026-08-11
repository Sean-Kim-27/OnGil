from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from api.place.models import MemoryPlace, Place
from api.scheduler.models import Scheduler, SchedulerPlace
from api.scheduler.schemas import (
    SchedulerCreateRequest,
    SchedulerPlaceCreateRequest,
    SchedulerPlaceSelection,
)


class SchedulerNotFoundError(RuntimeError):
    """Raised when a scheduler cannot be found for the current user."""


class MemoryPlaceNotFoundError(RuntimeError):
    """Raised when the scheduler's memory place anchor cannot be found."""


class SchedulerService:
    """Scheduler(일정) 생성/조회/장소 추가 등 CRUD를 담당."""

    def __init__(self, db: Session) -> None:
        self.db = db

    def create(self, user_id: int, request: SchedulerCreateRequest) -> Scheduler:
        if request.memory_place_id is not None:
            self._get_owned_memory_place(user_id, request.memory_place_id)

        scheduler = Scheduler(
            user_id=user_id,
            title=request.title,
            mobility_mode=request.mobility_mode,
            search_radius=request.search_radius,
            trip_type=request.trip_type,
            memory_place_id=request.memory_place_id,
            companion_type=request.companion_type,
            companion_count=request.companion_count,
            start_datetime=request.start_datetime,
            end_datetime=request.end_datetime,
        )
        self.db.add(scheduler)
        self.db.commit()
        self.db.refresh(scheduler)
        return scheduler

    def get_owned(self, user_id: int, scheduler_id: int) -> Scheduler:
        scheduler = self.db.scalar(
            select(Scheduler)
            .options(selectinload(Scheduler.places))
            .where(Scheduler.id == scheduler_id, Scheduler.user_id == user_id)
        )
        if scheduler is None:
            raise SchedulerNotFoundError(f"스케줄러(id={scheduler_id})를 찾을 수 없습니다.")
        return scheduler

    def list_owned(self, user_id: int) -> list[Scheduler]:
        return list(
            self.db.scalars(
                select(Scheduler)
                .options(selectinload(Scheduler.places))
                .where(Scheduler.user_id == user_id)
                .order_by(Scheduler.created_at.desc())
            )
        )

    def delete_owned(self, user_id: int, scheduler_id: int) -> None:
        scheduler = self.get_owned(user_id, scheduler_id)
        self.db.delete(scheduler)
        self.db.commit()

    def add_place(
        self,
        user_id: int,
        scheduler_id: int,
        request: SchedulerPlaceCreateRequest,
    ) -> SchedulerPlace:
        scheduler = self.get_owned(user_id, scheduler_id)
        place = _get_or_create_place(self.db, request.place)

        scheduler_place = SchedulerPlace(
            scheduler_id=scheduler.id,
            place_id=place.id,
            day_no=request.day_no,
            time_slot=request.time_slot,
            visit_order=request.visit_order,
        )
        self.db.add(scheduler_place)
        self.db.commit()
        self.db.refresh(scheduler_place)
        return scheduler_place

    def remove_place(
        self, user_id: int, scheduler_id: int, scheduler_place_id: int
    ) -> None:
        scheduler = self.get_owned(user_id, scheduler_id)
        scheduler_place = next(
            (place for place in scheduler.places if place.id == scheduler_place_id),
            None,
        )
        if scheduler_place is None:
            raise SchedulerNotFoundError(
                f"스케줄러 장소(id={scheduler_place_id})를 찾을 수 없습니다."
            )
        self.db.delete(scheduler_place)
        self.db.commit()

    def _get_owned_memory_place(self, user_id: int, memory_place_id: int) -> MemoryPlace:
        memory_place = self.db.scalar(
            select(MemoryPlace).where(
                MemoryPlace.id == memory_place_id,
                MemoryPlace.user_id == user_id,
            )
        )
        if memory_place is None:
            raise MemoryPlaceNotFoundError(
                f"추억의 장소(id={memory_place_id})를 찾을 수 없습니다."
            )
        return memory_place


def _get_or_create_place(db: Session, selection: SchedulerPlaceSelection) -> Place:
    """TourAPI content_id로 Place를 조회하고, 없으면 새로 만들어서 반환.

    scheduler_places.place_id는 우리 DB 내부 PK(Place.id)를 참조해야 하므로,
    프론트가 보낸 TourAPI content_id를 바로 저장하면 안 됨. 아카이브 기능
    (ArchivePhoto 등)도 Place를 참조하기 때문에, 처음 선택되는 시점에
    정식으로 Place 레코드를 만들어둬야 함.
    """
    place = db.scalar(select(Place).where(Place.api_place_id == selection.content_id))
    if place is not None:
        return place

    place = Place(
        api_place_id=selection.content_id,
        name=selection.title,
        category=selection.category.value,
        lat=selection.latitude,
        lng=selection.longitude,
        image_url=selection.image_url,
    )
    db.add(place)
    db.commit()
    db.refresh(place)
    return place