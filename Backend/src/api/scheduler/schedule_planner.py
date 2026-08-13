"""Convert an ordered route into concrete visit windows."""

from __future__ import annotations

from collections import defaultdict
from collections.abc import Iterable, Mapping, Sequence
from dataclasses import dataclass
from datetime import date, datetime, time, timedelta
from itertools import pairwise

from api.place.schemas import PlaceCategory
from api.scheduler.models import MobilityMode, ScheduleRole, TimeSlot
from api.scheduler.route_optimizer import RoutePoint, haversine_distance_m
from api.scheduler.schemas import SchedulerPlaceSelection
from infra.kakao_route import RouteLeg


class ScheduleWindowError(ValueError):
    """Raised when travel and visit time cannot fit in the requested window."""


@dataclass(frozen=True, slots=True)
class DailySchedulePolicy:
    """Default active hours used only when an itinerary spans multiple dates."""

    next_day_start: time = time(9, 0)
    non_final_day_end: time = time(20, 0)


DEFAULT_DAILY_POLICY = DailySchedulePolicy()


@dataclass(frozen=True, slots=True)
class MealWindowPolicy:
    breakfast_start: time = time(7, 30)
    breakfast_end: time = time(10, 0)
    lunch_start: time = time(11, 30)
    lunch_end: time = time(14, 0)
    dinner_start: time = time(17, 30)
    dinner_end: time = time(20, 30)
    meal_minutes: int = 60
    snack_minutes: int = 45


@dataclass(frozen=True, slots=True)
class AccommodationPolicy:
    preferred_check_in_start: time = time(15, 0)
    preferred_check_in_end: time = time(16, 0)
    check_in_process_minutes: int = 30
    preferred_check_out: time = time(11, 0)


DEFAULT_MEAL_POLICY = MealWindowPolicy()
DEFAULT_ACCOMMODATION_POLICY = AccommodationPolicy()


@dataclass(frozen=True, slots=True)
class AccommodationStayWindow:
    """One selected accommodation's inclusive check-in/exclusive check-out dates."""

    check_in_date: date
    check_out_date: date


DEFAULT_VISIT_MINUTES: Mapping[PlaceCategory, int] = {
    PlaceCategory.RESTAURANT: 60,
    PlaceCategory.CAFE: 45,
    PlaceCategory.TOURIST_ATTRACTION: 90,
    PlaceCategory.CULTURAL_FACILITY: 90,
    PlaceCategory.FESTIVAL: 120,
    PlaceCategory.TRAVEL_COURSE: 120,
    PlaceCategory.LEISURE_SPORTS: 90,
    PlaceCategory.ACCOMMODATION: 60,
    PlaceCategory.SHOPPING: 90,
    PlaceCategory.OTHER: 60,
}


@dataclass(frozen=True, slots=True)
class PlannedStop:
    selection: SchedulerPlaceSelection
    day_no: int
    time_slot: TimeSlot
    visit_order: int
    scheduled_start_datetime: datetime
    scheduled_end_datetime: datetime
    travel_seconds_from_previous: int
    travel_distance_m: int
    schedule_role: ScheduleRole
    check_in_datetime: datetime | None
    check_out_datetime: datetime | None


@dataclass(frozen=True, slots=True)
class _MealWindow:
    start: datetime
    end: datetime
    time_slot: TimeSlot


def plan_schedule(
    ordered_places: Sequence[SchedulerPlaceSelection],
    route_legs: Sequence[RouteLeg],
    *,
    start_datetime: datetime,
    end_datetime: datetime,
    visit_minutes: Mapping[PlaceCategory, int] = DEFAULT_VISIT_MINUTES,
    daily_policy: DailySchedulePolicy = DEFAULT_DAILY_POLICY,
    meal_policy: MealWindowPolicy = DEFAULT_MEAL_POLICY,
    accommodation_policy: AccommodationPolicy = DEFAULT_ACCOMMODATION_POLICY,
    accommodation_stays: Mapping[str, AccommodationStayWindow] | None = None,
    validate_stay_coverage: bool = True,
) -> tuple[PlannedStop, ...]:
    """Schedule travel then visits sequentially within the exact user window."""

    places = tuple(ordered_places)
    legs = tuple(route_legs)
    if len(places) != len(legs):
        raise ValueError("방문 장소마다 출발지 기준 이동 구간이 하나씩 필요합니다.")
    if end_datetime <= start_datetime:
        raise ValueError("일정 종료 일시는 시작 일시 이후여야 합니다.")

    cursor = start_datetime
    orders_by_day: defaultdict[int, int] = defaultdict(int)
    planned: list[PlannedStop] = []
    accommodation_count = sum(
        place.category == PlaceCategory.ACCOMMODATION for place in places
    )
    accommodation_ids = tuple(
        place.content_id
        for place in places
        if place.category == PlaceCategory.ACCOMMODATION
    )
    if accommodation_stays is not None and validate_stay_coverage:
        validate_accommodation_stay_windows(
            accommodation_ids,
            accommodation_stays,
            start_date=start_datetime.date(),
            end_date=end_datetime.date(),
        )
    if accommodation_stays is not None:
        not_before_by_date = _check_out_constraints_for_stays(
            accommodation_stays.values(),
            end_datetime=end_datetime,
            accommodation_policy=accommodation_policy,
        )
    else:
        not_before_by_date = _check_out_constraints(
            start_datetime,
            end_datetime,
            accommodation_count,
            accommodation_policy,
        )
    meal_windows = _meal_windows(
        start_datetime,
        end_datetime,
        daily_policy=daily_policy,
        meal_policy=meal_policy,
        not_before_by_date=not_before_by_date,
    )
    next_meal_window_index = 0
    if accommodation_count > 1:
        trip_nights = (end_datetime.date() - start_datetime.date()).days
        if accommodation_count > trip_nights:
            raise ValueError("숙박 장소는 여행 박 수를 초과할 수 없습니다.")
    if accommodation_count and start_datetime.date() == end_datetime.date():
        raise ValueError(
            "숙박 장소는 날짜가 다른 1박 이상 일정에만 배치할 수 있습니다."
        )

    accommodation_index = 0
    for selection, leg in zip(places, legs, strict=True):
        arrival = cursor + timedelta(seconds=leg.duration_seconds)
        check_in_datetime: datetime | None = None
        check_out_datetime: datetime | None = None

        if selection.category == PlaceCategory.ACCOMMODATION:
            stay_window = (
                accommodation_stays[selection.content_id]
                if accommodation_stays is not None
                else None
            )
            scheduled_start, scheduled_end, check_out_datetime = _place_accommodation(
                arrival,
                start_datetime=start_datetime,
                end_datetime=end_datetime,
                daily_policy=daily_policy,
                accommodation_policy=accommodation_policy,
                stay_index=accommodation_index,
                accommodation_count=accommodation_count,
                stay_window=stay_window,
            )
            accommodation_index += 1
            check_in_datetime = scheduled_start
            role = ScheduleRole.ACCOMMODATION
            assigned_time_slot = _time_slot(scheduled_start)
        elif selection.category == PlaceCategory.RESTAURANT:
            meal_placement = _place_in_meal_window(
                arrival,
                meal_windows,
                start_index=next_meal_window_index,
                meal_minutes=meal_policy.meal_minutes,
            )
            if meal_placement is not None:
                (
                    scheduled_start,
                    scheduled_end,
                    assigned_time_slot,
                    next_meal_window_index,
                ) = meal_placement
                role = ScheduleRole.MEAL
            else:
                scheduled_start, scheduled_end = _place_flexible_visit(
                    arrival,
                    duration_minutes=meal_policy.snack_minutes,
                    start_datetime=start_datetime,
                    end_datetime=end_datetime,
                    daily_policy=daily_policy,
                    not_before_by_date=not_before_by_date,
                )
                assigned_time_slot = _time_slot(scheduled_start)
                role = ScheduleRole.SNACK
        else:
            duration_minutes = visit_minutes.get(selection.category)
            if duration_minutes is None or duration_minutes <= 0:
                raise ValueError(
                    f"{selection.category.value} 체류시간 정책이 올바르지 않습니다."
                )
            scheduled_start, scheduled_end = _place_flexible_visit(
                arrival,
                duration_minutes=duration_minutes,
                start_datetime=start_datetime,
                end_datetime=end_datetime,
                daily_policy=daily_policy,
                not_before_by_date=not_before_by_date,
            )
            assigned_time_slot = _time_slot(scheduled_start)
            role = ScheduleRole.GENERAL_VISIT

        day_no = (scheduled_start.date() - start_datetime.date()).days + 1
        orders_by_day[day_no] += 1
        planned.append(
            PlannedStop(
                selection=selection,
                day_no=day_no,
                time_slot=assigned_time_slot,
                visit_order=orders_by_day[day_no],
                scheduled_start_datetime=scheduled_start,
                scheduled_end_datetime=scheduled_end,
                travel_seconds_from_previous=leg.duration_seconds,
                travel_distance_m=leg.distance_m,
                schedule_role=role,
                check_in_datetime=check_in_datetime,
                check_out_datetime=check_out_datetime,
            )
        )
        cursor = scheduled_end

    return tuple(planned)


def validate_minimum_schedule_window(
    places: Sequence[SchedulerPlaceSelection],
    *,
    start_datetime: datetime,
    end_datetime: datetime,
    visit_minutes: Mapping[PlaceCategory, int] = DEFAULT_VISIT_MINUTES,
    daily_policy: DailySchedulePolicy = DEFAULT_DAILY_POLICY,
    accommodation_stays: Mapping[str, AccommodationStayWindow] | None = None,
) -> None:
    """Reject an impossible visit-only window before calling a route API."""

    if end_datetime <= start_datetime:
        raise ValueError("일정 종료 일시는 시작 일시 이후여야 합니다.")
    total_minutes = 0
    for place in places:
        if place.category == PlaceCategory.ACCOMMODATION:
            duration_minutes = DEFAULT_ACCOMMODATION_POLICY.check_in_process_minutes
        elif place.category == PlaceCategory.RESTAURANT:
            duration_minutes = DEFAULT_MEAL_POLICY.snack_minutes
        else:
            duration_minutes = visit_minutes.get(place.category)
        if duration_minutes is None or duration_minutes <= 0:
            raise ValueError(
                f"{place.category.value} 체류시간 정책이 올바르지 않습니다."
            )
        total_minutes += duration_minutes

    has_accommodation = any(
        place.category == PlaceCategory.ACCOMMODATION for place in places
    )
    accommodation_ids = tuple(
        place.content_id
        for place in places
        if place.category == PlaceCategory.ACCOMMODATION
    )
    if accommodation_stays is not None:
        validate_accommodation_stay_windows(
            accommodation_ids,
            accommodation_stays,
            start_date=start_datetime.date(),
            end_date=end_datetime.date(),
        )
    available = _available_active_duration(
        start_datetime,
        end_datetime,
        daily_policy,
        not_before_by_date=(
            (
                _check_out_constraints_for_stays(
                    accommodation_stays.values(),
                    end_datetime=end_datetime,
                    accommodation_policy=DEFAULT_ACCOMMODATION_POLICY,
                )
                if accommodation_stays is not None
                else _check_out_constraints(
                    start_datetime,
                    end_datetime,
                    sum(
                        place.category == PlaceCategory.ACCOMMODATION
                        for place in places
                    ),
                    DEFAULT_ACCOMMODATION_POLICY,
                )
            )
            if has_accommodation
            else {}
        ),
    )
    minimum_duration = timedelta(minutes=total_minutes)
    if minimum_duration > available:
        raise ScheduleWindowError(
            "선택한 장소의 최소 체류시간만으로도 요청한 일정 범위를 초과합니다. "
            f"최소 필요 {minimum_duration}, 활동 가능 {available}"
        )


def reorder_accommodations_for_check_in(
    origin: RoutePoint,
    ordered_places: Sequence[SchedulerPlaceSelection],
    *,
    accommodation_order: Sequence[SchedulerPlaceSelection],
    mobility_mode: MobilityMode,
    start_datetime: datetime,
    end_datetime: datetime,
    accommodation_stays: Mapping[str, AccommodationStayWindow] | None = None,
) -> tuple[SchedulerPlaceSelection, ...]:
    """Insert one accommodation where estimated arrival best matches 15:00-16:00."""

    places = tuple(ordered_places)
    accommodations = tuple(accommodation_order)
    if not accommodations:
        return places
    trip_nights = (end_datetime.date() - start_datetime.date()).days
    if len(accommodations) > trip_nights:
        raise ValueError("숙박 장소는 여행 박 수를 초과할 수 없습니다.")
    if accommodation_stays is not None:
        validate_accommodation_stay_windows(
            tuple(place.content_id for place in accommodations),
            accommodation_stays,
            start_date=start_datetime.date(),
            end_date=end_datetime.date(),
        )

    accommodation_ids = {place.content_id for place in accommodations}
    current = tuple(
        place for place in places if place.content_id not in accommodation_ids
    )
    minimum_index = 0

    for stay_index, accommodation in enumerate(accommodations):
        best_candidate: tuple[SchedulerPlaceSelection, ...] | None = None
        best_score: tuple[float, float, int] | None = None
        check_in_date = (
            accommodation_stays[accommodation.content_id].check_in_date
            if accommodation_stays is not None
            else start_datetime.date() + timedelta(days=stay_index)
        )
        preferred_start = datetime.combine(
            check_in_date,
            DEFAULT_ACCOMMODATION_POLICY.preferred_check_in_start,
            tzinfo=start_datetime.tzinfo,
        )
        preferred_end = datetime.combine(
            check_in_date,
            DEFAULT_ACCOMMODATION_POLICY.preferred_check_in_end,
            tzinfo=start_datetime.tzinfo,
        )

        for index in range(minimum_index, len(current) + 1):
            candidate = current[:index] + (accommodation,) + current[index:]
            legs = _estimated_legs(origin, candidate, mobility_mode)
            try:
                planned = plan_schedule(
                    candidate,
                    legs,
                    start_datetime=start_datetime,
                    end_datetime=end_datetime,
                    accommodation_stays=(
                        {
                            place.content_id: accommodation_stays[place.content_id]
                            for place in candidate
                            if place.category == PlaceCategory.ACCOMMODATION
                        }
                        if accommodation_stays is not None
                        else None
                    ),
                    validate_stay_coverage=False,
                )
            except ScheduleWindowError:
                continue
            stay = next(
                stop
                for stop in planned
                if stop.selection.content_id == accommodation.content_id
            )
            check_in = stay.check_in_datetime
            if check_in is None:
                continue
            violation_seconds = (
                0.0
                if check_in <= preferred_end
                else (check_in - preferred_end).total_seconds()
            )
            target_distance_seconds = abs((check_in - preferred_start).total_seconds())
            route_distance = float(sum(leg.distance_m for leg in legs))
            score = (violation_seconds, target_distance_seconds + route_distance, index)
            if best_score is None or score < best_score:
                best_score = score
                best_candidate = candidate

        if best_candidate is None:
            raise ScheduleWindowError(
                f"{stay_index + 1}박차 숙박 체크인을 여행 범위에 배치할 수 없습니다."
            )
        current = best_candidate
        minimum_index = (
            next(
                index
                for index, place in enumerate(current)
                if place.content_id == accommodation.content_id
            )
            + 1
        )

    return current


def reorder_restaurants_for_meal_windows(
    origin: RoutePoint,
    ordered_places: Sequence[SchedulerPlaceSelection],
    *,
    mobility_mode: MobilityMode,
    start_datetime: datetime,
    end_datetime: datetime,
    daily_policy: DailySchedulePolicy = DEFAULT_DAILY_POLICY,
    meal_policy: MealWindowPolicy = DEFAULT_MEAL_POLICY,
    accommodation_stays: Mapping[str, AccommodationStayWindow] | None = None,
) -> tuple[SchedulerPlaceSelection, ...]:
    """Fill gaps with flexible stops and place restaurants at meal boundaries."""

    places = tuple(ordered_places)
    restaurants = [
        place for place in places if place.category == PlaceCategory.RESTAURANT
    ]
    if not restaurants:
        return places

    accommodation_count = sum(
        place.category == PlaceCategory.ACCOMMODATION for place in places
    )
    if accommodation_stays is not None:
        accommodation_ids = tuple(
            place.content_id
            for place in places
            if place.category == PlaceCategory.ACCOMMODATION
        )
        validate_accommodation_stay_windows(
            accommodation_ids,
            accommodation_stays,
            start_date=start_datetime.date(),
            end_date=end_datetime.date(),
        )
        not_before_by_date = _check_out_constraints_for_stays(
            accommodation_stays.values(),
            end_datetime=end_datetime,
            accommodation_policy=DEFAULT_ACCOMMODATION_POLICY,
        )
    else:
        not_before_by_date = _check_out_constraints(
            start_datetime,
            end_datetime,
            accommodation_count,
            DEFAULT_ACCOMMODATION_POLICY,
        )
    meal_windows = _meal_windows(
        start_datetime,
        end_datetime,
        daily_policy=daily_policy,
        meal_policy=meal_policy,
        not_before_by_date=not_before_by_date,
    )
    meal_restaurants = restaurants[: len(meal_windows)]
    meal_ids = {place.content_id for place in meal_restaurants}
    flexible_places = [place for place in places if place.content_id not in meal_ids]

    result: list[SchedulerPlaceSelection] = []
    cursor = start_datetime
    current_point = origin
    next_window_index = 0

    for restaurant in meal_restaurants:
        restaurant_point = _selection_point(restaurant)
        direct_arrival = cursor + _estimated_travel_duration(
            current_point,
            restaurant_point,
            mobility_mode,
        )
        placement = _place_in_meal_window(
            direct_arrival,
            meal_windows,
            start_index=next_window_index,
            meal_minutes=meal_policy.meal_minutes,
        )
        if placement is None:
            flexible_places.append(restaurant)
            continue

        _, meal_end, _, assigned_window_index = placement
        while flexible_places:
            candidate = flexible_places[0]
            candidate_point = _selection_point(candidate)
            candidate_arrival = cursor + _estimated_travel_duration(
                current_point,
                candidate_point,
                mobility_mode,
            )
            try:
                candidate_start, candidate_end = _place_flexible_visit(
                    candidate_arrival,
                    duration_minutes=_flexible_duration_minutes(
                        candidate,
                        meal_policy=meal_policy,
                    ),
                    start_datetime=start_datetime,
                    end_datetime=end_datetime,
                    daily_policy=daily_policy,
                    not_before_by_date=not_before_by_date,
                )
            except ScheduleWindowError:
                break
            del candidate_start
            restaurant_arrival = candidate_end + _estimated_travel_duration(
                candidate_point,
                restaurant_point,
                mobility_mode,
            )
            candidate_meal_start = max(
                restaurant_arrival,
                meal_windows[assigned_window_index - 1].start,
            )
            candidate_meal_end = candidate_meal_start + timedelta(
                minutes=meal_policy.meal_minutes
            )
            if candidate_meal_end > meal_windows[assigned_window_index - 1].end:
                break

            result.append(flexible_places.pop(0))
            cursor = candidate_end
            current_point = candidate_point
            meal_end = candidate_meal_end

        result.append(restaurant)
        cursor = meal_end
        current_point = restaurant_point
        next_window_index = assigned_window_index

    result.extend(flexible_places)
    return tuple(result)


def _selection_point(selection: SchedulerPlaceSelection) -> RoutePoint:
    return RoutePoint(
        selection.content_id,
        selection.latitude,
        selection.longitude,
    )


def _estimated_travel_duration(
    start: RoutePoint,
    end: RoutePoint,
    mobility_mode: MobilityMode,
) -> timedelta:
    speed_m_per_second = (
        4_500 / 3_600 if mobility_mode == MobilityMode.WALK else 25_000 / 3_600
    )
    return timedelta(
        seconds=round(haversine_distance_m(start, end) / speed_m_per_second)
    )


def _flexible_duration_minutes(
    selection: SchedulerPlaceSelection,
    *,
    meal_policy: MealWindowPolicy,
) -> int:
    if selection.category == PlaceCategory.RESTAURANT:
        return meal_policy.snack_minutes
    if selection.category == PlaceCategory.ACCOMMODATION:
        return DEFAULT_ACCOMMODATION_POLICY.check_in_process_minutes
    duration = DEFAULT_VISIT_MINUTES.get(selection.category)
    if duration is None:
        raise ValueError(f"{selection.category.value} 체류시간 정책이 없습니다.")
    return duration


def _estimated_legs(
    origin: RoutePoint,
    places: Sequence[SchedulerPlaceSelection],
    mobility_mode: MobilityMode,
) -> tuple[RouteLeg, ...]:
    speed_m_per_second = (
        4_500 / 3_600 if mobility_mode == MobilityMode.WALK else 25_000 / 3_600
    )
    current = origin
    legs: list[RouteLeg] = []
    for place in places:
        point = RoutePoint(place.content_id, place.latitude, place.longitude)
        distance_m = round(haversine_distance_m(current, point))
        legs.append(
            RouteLeg(
                duration_seconds=round(distance_m / speed_m_per_second),
                distance_m=distance_m,
            )
        )
        current = point
    return tuple(legs)


def _meal_windows(
    start_datetime: datetime,
    end_datetime: datetime,
    *,
    daily_policy: DailySchedulePolicy,
    meal_policy: MealWindowPolicy,
    not_before_by_date: Mapping[date, datetime] | None = None,
) -> tuple[_MealWindow, ...]:
    definitions = (
        (meal_policy.breakfast_start, meal_policy.breakfast_end, TimeSlot.MORNING),
        (meal_policy.lunch_start, meal_policy.lunch_end, TimeSlot.LUNCH),
        (meal_policy.dinner_start, meal_policy.dinner_end, TimeSlot.DINNER),
    )
    windows: list[_MealWindow] = []
    current_date = start_datetime.date()
    while current_date <= end_datetime.date():
        active_start = _active_day_start(
            current_date,
            start_datetime=start_datetime,
            daily_policy=daily_policy,
        )
        if not_before_by_date and current_date in not_before_by_date:
            active_start = max(active_start, not_before_by_date[current_date])
        active_end = _active_day_end(
            current_date,
            start_datetime=start_datetime,
            end_datetime=end_datetime,
            daily_policy=daily_policy,
        )
        for window_start, window_end, time_slot in definitions:
            candidate_start = max(
                active_start,
                datetime.combine(
                    current_date,
                    window_start,
                    tzinfo=start_datetime.tzinfo,
                ),
            )
            candidate_end = min(
                active_end,
                datetime.combine(
                    current_date,
                    window_end,
                    tzinfo=start_datetime.tzinfo,
                ),
            )
            if candidate_end - candidate_start >= timedelta(
                minutes=meal_policy.meal_minutes
            ):
                windows.append(_MealWindow(candidate_start, candidate_end, time_slot))
        current_date += timedelta(days=1)
    return tuple(windows)


def _place_in_meal_window(
    arrival: datetime,
    meal_windows: Sequence[_MealWindow],
    *,
    start_index: int,
    meal_minutes: int,
) -> tuple[datetime, datetime, TimeSlot, int] | None:
    duration = timedelta(minutes=meal_minutes)
    for index in range(start_index, len(meal_windows)):
        window = meal_windows[index]
        scheduled_start = max(arrival, window.start)
        scheduled_end = scheduled_start + duration
        if scheduled_end <= window.end:
            return scheduled_start, scheduled_end, window.time_slot, index + 1
    return None


def _place_accommodation(
    arrival: datetime,
    *,
    start_datetime: datetime,
    end_datetime: datetime,
    daily_policy: DailySchedulePolicy,
    accommodation_policy: AccommodationPolicy,
    stay_index: int,
    accommodation_count: int,
    stay_window: AccommodationStayWindow | None = None,
) -> tuple[datetime, datetime, datetime]:
    check_in_date = (
        stay_window.check_in_date
        if stay_window is not None
        else start_datetime.date() + timedelta(days=stay_index)
    )
    preferred_start = datetime.combine(
        check_in_date,
        accommodation_policy.preferred_check_in_start,
        tzinfo=start_datetime.tzinfo,
    )
    scheduled_start = max(arrival, preferred_start)
    scheduled_end = scheduled_start + timedelta(
        minutes=accommodation_policy.check_in_process_minutes
    )
    first_day_end = _active_day_end(
        check_in_date,
        start_datetime=start_datetime,
        end_datetime=end_datetime,
        daily_policy=daily_policy,
    )
    if scheduled_end > first_day_end or scheduled_start.date() != check_in_date:
        raise ScheduleWindowError(
            f"{stay_index + 1}박차 숙박 체크인을 해당 날짜 활동시간 안에 배치할 수 없습니다."
        )

    check_out_date = (
        stay_window.check_out_date
        if stay_window is not None
        else (
            end_datetime.date()
            if stay_index == accommodation_count - 1
            else check_in_date + timedelta(days=1)
        )
    )
    check_out = datetime.combine(
        check_out_date,
        accommodation_policy.preferred_check_out,
        tzinfo=end_datetime.tzinfo,
    )
    if check_out_date == end_datetime.date():
        check_out = min(end_datetime, check_out)
    if check_out <= scheduled_start:
        raise ScheduleWindowError("숙박 체크아웃은 체크인 이후여야 합니다.")
    return scheduled_start, scheduled_end, check_out


def _place_flexible_visit(
    arrival: datetime,
    *,
    duration_minutes: int,
    start_datetime: datetime,
    end_datetime: datetime,
    daily_policy: DailySchedulePolicy,
    not_before_by_date: Mapping[date, datetime] | None = None,
) -> tuple[datetime, datetime]:
    scheduled_start = arrival
    duration = timedelta(minutes=duration_minutes)
    while True:
        active_start = _active_day_start(
            scheduled_start.date(),
            start_datetime=start_datetime,
            daily_policy=daily_policy,
        )
        if not_before_by_date and scheduled_start.date() in not_before_by_date:
            active_start = max(
                active_start,
                not_before_by_date[scheduled_start.date()],
            )
        scheduled_start = max(scheduled_start, active_start)
        scheduled_end = scheduled_start + duration
        active_end = _active_day_end(
            scheduled_start.date(),
            start_datetime=start_datetime,
            end_datetime=end_datetime,
            daily_policy=daily_policy,
        )
        if scheduled_end <= active_end:
            return scheduled_start, scheduled_end
        scheduled_start = _next_active_day_start(
            scheduled_start.date(),
            start_datetime=start_datetime,
            daily_policy=daily_policy,
        )
        if scheduled_start >= end_datetime:
            available = _available_active_duration(
                start_datetime,
                end_datetime,
                daily_policy,
            )
            raise ScheduleWindowError(
                "선택한 장소의 이동·체류시간이 요청한 일정 범위를 초과합니다. "
                f"활동 가능 {available}"
            )


def _active_day_start(
    current_date: date,
    *,
    start_datetime: datetime,
    daily_policy: DailySchedulePolicy,
) -> datetime:
    if current_date == start_datetime.date():
        return start_datetime
    return datetime.combine(
        current_date,
        daily_policy.next_day_start,
        tzinfo=start_datetime.tzinfo,
    )


def _active_day_end(
    current_date: date,
    *,
    start_datetime: datetime,
    end_datetime: datetime,
    daily_policy: DailySchedulePolicy,
) -> datetime:
    if (
        start_datetime.date() == end_datetime.date()
        or current_date == end_datetime.date()
    ):
        return end_datetime
    return datetime.combine(
        current_date,
        daily_policy.non_final_day_end,
        tzinfo=start_datetime.tzinfo,
    )


def _next_active_day_start(
    current_date: date,
    *,
    start_datetime: datetime,
    daily_policy: DailySchedulePolicy,
) -> datetime:
    return datetime.combine(
        current_date + timedelta(days=1),
        daily_policy.next_day_start,
        tzinfo=start_datetime.tzinfo,
    )


def _available_active_duration(
    start_datetime: datetime,
    end_datetime: datetime,
    daily_policy: DailySchedulePolicy,
    not_before_by_date: Mapping[date, datetime] | None = None,
) -> timedelta:
    if start_datetime.date() == end_datetime.date():
        return end_datetime - start_datetime

    total = timedelta()
    current_date = start_datetime.date()
    while current_date <= end_datetime.date():
        active_start = (
            start_datetime
            if current_date == start_datetime.date()
            else datetime.combine(
                current_date,
                daily_policy.next_day_start,
                tzinfo=start_datetime.tzinfo,
            )
        )
        if not_before_by_date and current_date in not_before_by_date:
            active_start = max(active_start, not_before_by_date[current_date])
        active_end = (
            end_datetime
            if current_date == end_datetime.date()
            else datetime.combine(
                current_date,
                daily_policy.non_final_day_end,
                tzinfo=start_datetime.tzinfo,
            )
        )
        if active_end > active_start:
            total += active_end - active_start
        current_date += timedelta(days=1)
    return total


def _check_out_constraints(
    start_datetime: datetime,
    end_datetime: datetime,
    accommodation_count: int,
    accommodation_policy: AccommodationPolicy,
) -> dict[date, datetime]:
    constraints: dict[date, datetime] = {}
    for stay_index in range(accommodation_count):
        check_out_date = (
            end_datetime.date()
            if stay_index == accommodation_count - 1
            else start_datetime.date() + timedelta(days=stay_index + 1)
        )
        check_out = datetime.combine(
            check_out_date,
            accommodation_policy.preferred_check_out,
            tzinfo=end_datetime.tzinfo,
        )
        if check_out_date == end_datetime.date():
            check_out = min(end_datetime, check_out)
        constraints[check_out_date] = check_out
    return constraints


def _check_out_constraints_for_stays(
    stay_windows: Iterable[AccommodationStayWindow],
    *,
    end_datetime: datetime,
    accommodation_policy: AccommodationPolicy,
) -> dict[date, datetime]:
    constraints: dict[date, datetime] = {}
    for window in stay_windows:
        check_out = datetime.combine(
            window.check_out_date,
            accommodation_policy.preferred_check_out,
            tzinfo=end_datetime.tzinfo,
        )
        if window.check_out_date == end_datetime.date():
            check_out = min(end_datetime, check_out)
        constraints[window.check_out_date] = check_out
    return constraints


def validate_accommodation_stay_windows(
    accommodation_ids: Sequence[str],
    stay_windows: Mapping[str, AccommodationStayWindow],
    *,
    start_date: date,
    end_date: date,
) -> None:
    """Validate a full, gapless replacement of every selected accommodation."""

    expected_ids = set(accommodation_ids)
    actual_ids = set(stay_windows)
    if actual_ids != expected_ids:
        raise ValueError(
            "숙박 배정은 일정에 포함된 모든 숙소를 정확히 한 번 포함해야 합니다."
        )
    if not stay_windows:
        raise ValueError("숙박 배정에는 숙소가 하나 이상 필요합니다.")

    ordered = sorted(
        stay_windows.values(),
        key=lambda window: (window.check_in_date, window.check_out_date),
    )
    if ordered[0].check_in_date != start_date:
        raise ValueError("첫 숙소의 체크인 날짜는 여행 시작일이어야 합니다.")
    if ordered[-1].check_out_date != end_date:
        raise ValueError("마지막 숙소의 체크아웃 날짜는 여행 종료일이어야 합니다.")

    for window in ordered:
        if window.check_out_date <= window.check_in_date:
            raise ValueError("숙박 체크아웃 날짜는 체크인 날짜 이후여야 합니다.")
        if window.check_in_date < start_date or window.check_out_date > end_date:
            raise ValueError("숙박 범위는 여행 시작일과 종료일 안에 있어야 합니다.")

    for previous, current in pairwise(ordered):
        if previous.check_out_date != current.check_in_date:
            raise ValueError("숙박 범위는 날짜가 비거나 겹치지 않게 연속되어야 합니다.")


def _time_slot(value: datetime) -> TimeSlot:
    hour = value.hour
    if hour < 11:
        return TimeSlot.MORNING
    if hour < 14:
        return TimeSlot.LUNCH
    if hour < 17:
        return TimeSlot.AFTERNOON
    if hour < 20:
        return TimeSlot.DINNER
    return TimeSlot.NIGHT
