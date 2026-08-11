from __future__ import annotations

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as postgresql_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from api.place.models import MemoryPlace, Place
from api.scheduler.models import Scheduler, SchedulerPlace
from api.scheduler.schemas import (
    MemoryPlaceSelection,
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
        try:
            memory_place = self._resolve_memory_place(user_id, request)
            scheduler = Scheduler(
                user_id=user_id,
                title=request.title,
                mobility_mode=request.mobility_mode,
                search_radius=request.search_radius,
                trip_type=request.trip_type,
                memory_place_id=memory_place.id,
                companion_type=request.companion_type,
                companion_count=request.companion_count,
                start_datetime=request.start_datetime,
                end_datetime=request.end_datetime,
            )
            self.db.add(scheduler)
            self.db.flush()

            for item in request.places:
                place = _upsert_place(self.db, item.place)
                self.db.add(
                    SchedulerPlace(
                        scheduler_id=scheduler.id,
                        place_id=place.id,
                        day_no=item.day_no,
                        time_slot=item.time_slot,
                        visit_order=item.visit_order,
                    )
                )
            scheduler_id = scheduler.id
            self.db.commit()
        except Exception:
            self.db.rollback()
            raise

        return self.get_owned(user_id, scheduler_id)

    def get_owned(self, user_id: int, scheduler_id: int) -> Scheduler:
        scheduler = self.db.scalar(
            select(Scheduler)
            .options(
                selectinload(Scheduler.memory_place),
                selectinload(Scheduler.places).selectinload(SchedulerPlace.place),
            )
            .where(Scheduler.id == scheduler_id, Scheduler.user_id == user_id)
        )
        if scheduler is None:
            raise SchedulerNotFoundError(
                f"스케줄러(id={scheduler_id})를 찾을 수 없습니다."
            )
        return scheduler

    def list_owned(self, user_id: int) -> list[Scheduler]:
        return list(
            self.db.scalars(
                select(Scheduler)
                .options(
                    selectinload(Scheduler.memory_place),
                    selectinload(Scheduler.places).selectinload(SchedulerPlace.place),
                )
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
        try:
            scheduler = self.get_owned(user_id, scheduler_id)
            place = _upsert_place(self.db, request.place)

            scheduler_place = SchedulerPlace(
                scheduler_id=scheduler.id,
                place_id=place.id,
                day_no=request.day_no,
                time_slot=request.time_slot,
                visit_order=request.visit_order,
            )
            self.db.add(scheduler_place)
            self.db.commit()
        except Exception:
            self.db.rollback()
            raise
        saved_scheduler_place = self.db.scalar(
            select(SchedulerPlace)
            .options(selectinload(SchedulerPlace.place))
            .where(SchedulerPlace.id == scheduler_place.id)
        )
        if saved_scheduler_place is None:
            raise RuntimeError("스케줄러 장소를 저장한 뒤 다시 조회할 수 없습니다.")
        return saved_scheduler_place

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

    def _get_owned_memory_place(
        self, user_id: int, memory_place_id: int
    ) -> MemoryPlace:
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

    def _resolve_memory_place(
        self, user_id: int, request: SchedulerCreateRequest
    ) -> MemoryPlace:
        if request.memory_place_id is not None:
            return self._get_owned_memory_place(user_id, request.memory_place_id)

        if request.memory_place is None:
            raise ValueError("새로 저장할 추억의 장소 정보가 필요합니다.")
        return self._create_memory_place(user_id, request.memory_place)

    def _create_memory_place(
        self, user_id: int, selection: MemoryPlaceSelection
    ) -> MemoryPlace:
        memory_place = MemoryPlace(
            user_id=user_id,
            name=selection.name,
            address=selection.address or selection.name,
            lat=selection.latitude,
            lng=selection.longitude,
        )
        self.db.add(memory_place)
        self.db.flush()
        return memory_place


def _upsert_place(db: Session, selection: SchedulerPlaceSelection) -> Place:
    """TourAPI content_id로 Place를 upsert하고 내부 Place를 반환.

    scheduler_places.place_id는 우리 DB 내부 PK(Place.id)를 참조해야 하므로,
    프론트가 보낸 TourAPI content_id를 바로 저장하면 안 됨. 아카이브 기능
    (ArchivePhoto 등)도 Place를 참조하기 때문에, 처음 선택되는 시점에
    정식으로 Place 레코드를 만들어둬야 함.
    """
    values = {
        "api_place_id": selection.content_id,
        "name": selection.title,
        "category": selection.category.value,
        "lat": selection.latitude,
        "lng": selection.longitude,
        "image_url": selection.image_url,
        "kakao_place_id": selection.kakao_place_id,
        "kakao_place_url": selection.place_url,
    }
    place = db.scalar(select(Place).where(Place.api_place_id == selection.content_id))
    if place is not None:
        _update_place(place, values)
        return place

    dialect_name = db.get_bind().dialect.name
    update_values = _place_update_values(values)
    if dialect_name == "postgresql":
        statement = postgresql_insert(Place).values(**values)
        db.execute(
            statement.on_conflict_do_update(
                index_elements=[Place.api_place_id], set_=update_values
            )
        )
    elif dialect_name == "sqlite":
        statement = sqlite_insert(Place).values(**values)
        db.execute(
            statement.on_conflict_do_update(
                index_elements=[Place.api_place_id], set_=update_values
            )
        )
    else:
        return _insert_place_with_savepoint(db, selection, values)

    place = db.scalar(select(Place).where(Place.api_place_id == selection.content_id))
    if place is None:
        raise RuntimeError("장소를 저장한 뒤 다시 조회할 수 없습니다.")
    return place


def _insert_place_with_savepoint(
    db: Session,
    selection: SchedulerPlaceSelection,
    values: dict[str, object],
) -> Place:
    """Fallback get-or-create for dialects without a native upsert path."""
    place = Place(**values)
    try:
        with db.begin_nested():
            db.add(place)
            db.flush()
    except IntegrityError:
        # Another request may have inserted the same TourAPI content_id between
        # the SELECT above and this INSERT. The savepoint keeps the outer
        # scheduler transaction usable so the winning row can be reused.
        place = db.scalar(
            select(Place).where(Place.api_place_id == selection.content_id)
        )
        if place is None:
            raise
        _update_place(place, values)
    return place


def _update_place(place: Place, values: dict[str, object]) -> None:
    for key, value in _place_update_values(values).items():
        setattr(place, key, value)


def _place_update_values(values: dict[str, object]) -> dict[str, object]:
    return {
        key: value
        for key, value in values.items()
        if key != "api_place_id" and not (key == "image_url" and value is None)
    }
