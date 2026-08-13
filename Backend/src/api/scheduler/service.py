from __future__ import annotations

import math
from dataclasses import dataclass
from datetime import datetime, timezone
from itertools import pairwise

from sqlalchemy import select
from sqlalchemy.dialects.postgresql import insert as postgresql_insert
from sqlalchemy.dialects.sqlite import insert as sqlite_insert
from sqlalchemy.exc import IntegrityError
from sqlalchemy.orm import Session, selectinload

from api.place.models import MemoryPlace, Place
from api.place.schemas import PlaceCategory
from api.scheduler.models import MobilityMode, Scheduler, SchedulerPlace, TimeSlot
from api.scheduler.route_optimizer import (
    RoutePoint,
    haversine_distance_m,
    optimize_geodesic_route,
)
from api.scheduler.schedule_planner import (
    AccommodationStayWindow,
    ScheduleWindowError,
    plan_schedule,
    reorder_accommodations_for_check_in,
    reorder_restaurants_for_meal_windows,
    validate_minimum_schedule_window,
)
from api.scheduler.schemas import (
    MemoryPlaceSelection,
    SchedulerCreateRequest,
    SchedulerPlaceCreateRequest,
    SchedulerPlaceSelection,
    SchedulerPlaceUpdateRequest,
    SchedulerStaysReplaceRequest,
)
from infra.kakao_route import KakaoRouteError, RouteLeg, RouteVerifier


class SchedulerNotFoundError(RuntimeError):
    """Raised when a scheduler cannot be found for the current user."""


class MemoryPlaceNotFoundError(RuntimeError):
    """Raised when the scheduler's memory place anchor cannot be found."""


class ScheduleOptimizationError(ValueError):
    """Raised when selected places cannot form a valid requested schedule."""


@dataclass(frozen=True, slots=True)
class _AnchorSnapshot:
    latitude: float
    longitude: float


class SchedulerService:
    """Scheduler(일정) 생성/조회/장소 추가 등 CRUD를 담당."""

    def __init__(
        self,
        db: Session,
        route_verifier: RouteVerifier | None = None,
    ) -> None:
        self.db = db
        self.route_verifier = route_verifier

    def create(self, user_id: int, request: SchedulerCreateRequest) -> Scheduler:
        anchor = self._get_anchor_snapshot(user_id, request)
        origin = RoutePoint(
            key="__memory_place_anchor__",
            latitude=anchor.latitude,
            longitude=anchor.longitude,
        )
        selections_by_key = {place.content_id: place for place in request.places}
        try:
            optimized = optimize_geodesic_route(
                origin,
                [
                    RoutePoint(
                        key=place.content_id,
                        latitude=place.latitude,
                        longitude=place.longitude,
                    )
                    for place in request.places
                ],
            )
            ordered_places = tuple(
                selections_by_key[point.key] for point in optimized.ordered_stops
            )
            ordered_places = reorder_restaurants_for_meal_windows(
                origin,
                ordered_places,
                mobility_mode=request.mobility_mode,
                start_datetime=request.start_datetime,
                end_datetime=request.end_datetime,
            )
            ordered_places = reorder_accommodations_for_check_in(
                origin,
                ordered_places,
                accommodation_order=tuple(
                    place
                    for place in request.places
                    if place.category == PlaceCategory.ACCOMMODATION
                ),
                mobility_mode=request.mobility_mode,
                start_datetime=request.start_datetime,
                end_datetime=request.end_datetime,
            )
            validate_minimum_schedule_window(
                ordered_places,
                start_datetime=request.start_datetime,
                end_datetime=request.end_datetime,
            )
            route_verified, route_legs = self._route_legs(
                request.mobility_mode,
                (
                    origin,
                    *(
                        RoutePoint(
                            key=place.content_id,
                            latitude=place.latitude,
                            longitude=place.longitude,
                        )
                        for place in ordered_places
                    ),
                ),
            )
            planned_places = plan_schedule(
                ordered_places,
                route_legs,
                start_datetime=request.start_datetime,
                end_datetime=request.end_datetime,
            )
        except (ScheduleWindowError, ValueError) as exc:
            raise ScheduleOptimizationError(str(exc)) from exc

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
                optimization_basis="GEODESIC_APPROXIMATION",
                route_verified=route_verified,
            )
            self.db.add(scheduler)
            self.db.flush()

            for item in planned_places:
                place = _upsert_place(self.db, item.selection)
                self.db.add(
                    SchedulerPlace(
                        scheduler_id=scheduler.id,
                        place_id=place.id,
                        day_no=item.day_no,
                        time_slot=item.time_slot,
                        visit_order=item.visit_order,
                        scheduled_start_datetime=item.scheduled_start_datetime,
                        scheduled_end_datetime=item.scheduled_end_datetime,
                        travel_seconds_from_previous=(
                            item.travel_seconds_from_previous
                        ),
                        travel_distance_m=item.travel_distance_m,
                        schedule_role=item.schedule_role,
                        check_in_datetime=item.check_in_datetime,
                        check_out_datetime=item.check_out_datetime,
                    )
                )
            scheduler_id = scheduler.id
            self.db.commit()
        except Exception:
            self.db.rollback()
            raise

        return self.get_owned(user_id, scheduler_id)

    def replace_stays(
        self,
        user_id: int,
        scheduler_id: int,
        request: SchedulerStaysReplaceRequest,
    ) -> Scheduler:
        """Replace every accommodation range and re-optimize the saved itinerary."""

        scheduler = self.get_owned(user_id, scheduler_id)
        accommodations = tuple(
            scheduler_place
            for scheduler_place in scheduler.places
            if scheduler_place.place.category == PlaceCategory.ACCOMMODATION.value
        )
        expected_ids = {scheduler_place.id for scheduler_place in accommodations}
        actual_ids = {stay.scheduler_place_id for stay in request.stays}
        if not accommodations:
            raise ScheduleOptimizationError("이 일정에는 수정할 숙소가 없습니다.")
        if actual_ids != expected_ids:
            raise ScheduleOptimizationError(
                "숙박 배정은 일정에 포함된 모든 숙소를 정확히 한 번 포함해야 합니다."
            )
        if scheduler.memory_place is None:
            raise MemoryPlaceNotFoundError("일정의 출발 기준 장소를 찾을 수 없습니다.")

        scheduler_places_by_id = {
            scheduler_place.id: scheduler_place for scheduler_place in scheduler.places
        }
        selections_by_scheduler_place_id = {
            scheduler_place.id: _selection_from_stored_place(scheduler_place.place)
            for scheduler_place in scheduler.places
        }
        ordered_stays = tuple(
            sorted(
                request.stays,
                key=lambda stay: (stay.check_in_date, stay.check_out_date),
            )
        )
        accommodation_stays = {
            scheduler_places_by_id[stay.scheduler_place_id].place.api_place_id: (
                AccommodationStayWindow(
                    check_in_date=stay.check_in_date,
                    check_out_date=stay.check_out_date,
                )
            )
            for stay in ordered_stays
        }
        origin = RoutePoint(
            key="__memory_place_anchor__",
            latitude=scheduler.memory_place.lat,
            longitude=scheduler.memory_place.lng,
        )
        selections = tuple(selections_by_scheduler_place_id.values())
        selections_by_key = {
            selection.content_id: selection for selection in selections
        }

        try:
            optimized = optimize_geodesic_route(
                origin,
                tuple(_selection_route_point(selection) for selection in selections),
            )
            ordered_places = tuple(
                selections_by_key[point.key] for point in optimized.ordered_stops
            )
            ordered_places = reorder_restaurants_for_meal_windows(
                origin,
                ordered_places,
                mobility_mode=scheduler.mobility_mode,
                start_datetime=scheduler.start_datetime,
                end_datetime=scheduler.end_datetime,
                accommodation_stays=accommodation_stays,
            )
            ordered_places = reorder_accommodations_for_check_in(
                origin,
                ordered_places,
                accommodation_order=tuple(
                    selections_by_scheduler_place_id[stay.scheduler_place_id]
                    for stay in ordered_stays
                ),
                mobility_mode=scheduler.mobility_mode,
                start_datetime=scheduler.start_datetime,
                end_datetime=scheduler.end_datetime,
                accommodation_stays=accommodation_stays,
            )
            validate_minimum_schedule_window(
                ordered_places,
                start_datetime=scheduler.start_datetime,
                end_datetime=scheduler.end_datetime,
                accommodation_stays=accommodation_stays,
            )
            route_verified, route_legs = self._route_legs(
                scheduler.mobility_mode,
                (
                    origin,
                    *tuple(_selection_route_point(place) for place in ordered_places),
                ),
            )
            planned_places = plan_schedule(
                ordered_places,
                route_legs,
                start_datetime=scheduler.start_datetime,
                end_datetime=scheduler.end_datetime,
                accommodation_stays=accommodation_stays,
            )
        except (ScheduleWindowError, ValueError) as exc:
            raise ScheduleOptimizationError(str(exc)) from exc

        scheduler_places_by_content_id = {
            scheduler_place.place.api_place_id: scheduler_place
            for scheduler_place in scheduler.places
        }
        try:
            for planned in planned_places:
                scheduler_place = scheduler_places_by_content_id[
                    planned.selection.content_id
                ]
                scheduler_place.day_no = planned.day_no
                scheduler_place.time_slot = planned.time_slot
                scheduler_place.visit_order = planned.visit_order
                scheduler_place.scheduled_start_datetime = (
                    planned.scheduled_start_datetime
                )
                scheduler_place.scheduled_end_datetime = planned.scheduled_end_datetime
                scheduler_place.travel_seconds_from_previous = (
                    planned.travel_seconds_from_previous
                )
                scheduler_place.travel_distance_m = planned.travel_distance_m
                scheduler_place.schedule_role = planned.schedule_role
                scheduler_place.check_in_datetime = planned.check_in_datetime
                scheduler_place.check_out_datetime = planned.check_out_datetime
            scheduler.route_verified = route_verified
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
            self._validate_scheduled_window(
                scheduler,
                request.scheduled_start_datetime,
                request.scheduled_end_datetime,
            )
            place = _upsert_place(self.db, request.place)

            scheduler_place = SchedulerPlace(
                scheduler_id=scheduler.id,
                place_id=place.id,
                day_no=request.day_no,
                time_slot=request.time_slot,
                visit_order=request.visit_order,
                scheduled_start_datetime=request.scheduled_start_datetime,
                scheduled_end_datetime=request.scheduled_end_datetime,
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

    def update_place(
        self,
        user_id: int,
        scheduler_id: int,
        scheduler_place_id: int,
        request: SchedulerPlaceUpdateRequest,
    ) -> SchedulerPlace:
        try:
            scheduler = self.get_owned(user_id, scheduler_id)
            scheduler_place = next(
                (place for place in scheduler.places if place.id == scheduler_place_id),
                None,
            )
            if scheduler_place is None:
                raise SchedulerNotFoundError(
                    f"스케줄러 장소(id={scheduler_place_id})를 찾을 수 없습니다."
                )

            fields = request.model_fields_set
            scheduled_start = (
                request.scheduled_start_datetime
                if "scheduled_start_datetime" in fields
                else scheduler_place.scheduled_start_datetime
            )
            scheduled_end = (
                request.scheduled_end_datetime
                if "scheduled_end_datetime" in fields
                else scheduler_place.scheduled_end_datetime
            )
            self._validate_scheduled_window(
                scheduler,
                scheduled_start,
                scheduled_end,
            )

            for field_name in fields:
                setattr(scheduler_place, field_name, getattr(request, field_name))

            if "scheduled_start_datetime" in fields and scheduled_start is not None:
                if "day_no" not in fields:
                    scheduler_place.day_no = _day_no(
                        scheduler.start_datetime,
                        scheduled_start,
                    )
                if "time_slot" not in fields:
                    scheduler_place.time_slot = _time_slot_for_hour(
                        scheduled_start.hour
                    )

            self.db.commit()
            saved_id = scheduler_place.id
        except Exception:
            self.db.rollback()
            raise

        saved_scheduler_place = self.db.scalar(
            select(SchedulerPlace)
            .options(selectinload(SchedulerPlace.place))
            .where(SchedulerPlace.id == saved_id)
        )
        if saved_scheduler_place is None:
            raise RuntimeError("스케줄러 장소를 수정한 뒤 다시 조회할 수 없습니다.")
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

    def _get_anchor_snapshot(
        self,
        user_id: int,
        request: SchedulerCreateRequest,
    ) -> _AnchorSnapshot:
        if request.memory_place_id is not None:
            memory_place = self._get_owned_memory_place(
                user_id,
                request.memory_place_id,
            )
            return _AnchorSnapshot(
                latitude=memory_place.lat,
                longitude=memory_place.lng,
            )
        if request.memory_place is None:
            raise ValueError("새로 저장할 추억의 장소 정보가 필요합니다.")
        return _AnchorSnapshot(
            latitude=request.memory_place.latitude,
            longitude=request.memory_place.longitude,
        )

    def _route_legs(
        self,
        mobility_mode: MobilityMode,
        route: tuple[RoutePoint, ...],
    ) -> tuple[bool, tuple[RouteLeg, ...]]:
        if self.route_verifier is not None:
            try:
                return True, self.route_verifier.verify(mobility_mode, route)
            except KakaoRouteError:
                # A Kakao outage must not discard a locally optimized itinerary.
                pass
        return False, _estimate_route_legs(mobility_mode, route)

    @staticmethod
    def _validate_scheduled_window(
        scheduler: Scheduler,
        scheduled_start: datetime | None,
        scheduled_end: datetime | None,
    ) -> None:
        if (scheduled_start is None) != (scheduled_end is None):
            raise ScheduleOptimizationError(
                "장소 방문 시작·종료 일시는 함께 지정해야 합니다."
            )
        if scheduled_start is None or scheduled_end is None:
            return
        values = _comparable_datetimes(
            scheduler.start_datetime,
            scheduler.end_datetime,
            scheduled_start,
            scheduled_end,
        )
        scheduler_start, scheduler_end, place_start, place_end = values
        if place_end <= place_start:
            raise ScheduleOptimizationError(
                "장소 방문 종료 일시는 시작 일시 이후여야 합니다."
            )
        if place_start < scheduler_start or place_end > scheduler_end:
            raise ScheduleOptimizationError(
                "장소 방문 일시는 스케줄러의 start_datetime과 end_datetime 안에 있어야 합니다."
            )

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


def _selection_from_stored_place(place: Place) -> SchedulerPlaceSelection:
    has_complete_kakao_link = bool(place.kakao_place_id and place.kakao_place_url)
    return SchedulerPlaceSelection(
        content_id=place.api_place_id,
        title=place.name,
        category=PlaceCategory(place.category),
        latitude=place.lat,
        longitude=place.lng,
        image_url=place.image_url,
        kakao_place_id=(place.kakao_place_id if has_complete_kakao_link else None),
        place_url=(place.kakao_place_url if has_complete_kakao_link else None),
    )


def _selection_route_point(selection: SchedulerPlaceSelection) -> RoutePoint:
    return RoutePoint(
        key=selection.content_id,
        latitude=selection.latitude,
        longitude=selection.longitude,
    )


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
    nullable_enrichment_fields = {
        "image_url",
        "kakao_place_id",
        "kakao_place_url",
    }
    return {
        key: value
        for key, value in values.items()
        if key != "api_place_id"
        and not (key in nullable_enrichment_fields and value is None)
    }


def _estimate_route_legs(
    mobility_mode: MobilityMode,
    route: tuple[RoutePoint, ...],
) -> tuple[RouteLeg, ...]:
    speed_m_per_second = (
        4_500 / 3_600 if mobility_mode == MobilityMode.WALK else 25_000 / 3_600
    )
    legs: list[RouteLeg] = []
    for start, end in pairwise(route):
        distance_m = round(haversine_distance_m(start, end))
        legs.append(
            RouteLeg(
                duration_seconds=math.ceil(distance_m / speed_m_per_second),
                distance_m=distance_m,
            )
        )
    return tuple(legs)


def _comparable_datetimes(*values: datetime) -> tuple[datetime, ...]:
    reference_timezone = next(
        (value.tzinfo for value in values if value.tzinfo is not None),
        timezone.utc,
    )
    return tuple(
        (
            value
            if value.tzinfo is not None
            else value.replace(tzinfo=reference_timezone)
        ).astimezone(timezone.utc)
        for value in values
    )


def _day_no(scheduler_start: datetime, place_start: datetime) -> int:
    reference_timezone = scheduler_start.tzinfo or place_start.tzinfo or timezone.utc
    normalized_scheduler_start = (
        scheduler_start
        if scheduler_start.tzinfo is not None
        else scheduler_start.replace(tzinfo=reference_timezone)
    )
    normalized_place_start = (
        place_start
        if place_start.tzinfo is not None
        else place_start.replace(tzinfo=reference_timezone)
    ).astimezone(reference_timezone)
    return (normalized_place_start.date() - normalized_scheduler_start.date()).days + 1


def _time_slot_for_hour(hour: int) -> TimeSlot:
    if hour < 11:
        return TimeSlot.MORNING
    if hour < 14:
        return TimeSlot.LUNCH
    if hour < 17:
        return TimeSlot.AFTERNOON
    if hour < 20:
        return TimeSlot.DINNER
    return TimeSlot.NIGHT
