import os
from datetime import datetime, timedelta, timezone

os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("GOOGLE_CLIENT_ID", "test.apps.googleusercontent.com")
os.environ.setdefault("KAKAO_APP_ID", "1234")
os.environ.setdefault("JWT_SECRET_KEY", "test-only-secret-key-with-32-characters")

import pytest

from api.place.schemas import PlaceCategory
from api.scheduler.models import ScheduleRole, TimeSlot
from api.scheduler.schedule_planner import ScheduleWindowError, plan_schedule
from api.scheduler.schemas import SchedulerPlaceSelection
from infra.kakao_route import RouteLeg


def selection(content_id: str, category: PlaceCategory) -> SchedulerPlaceSelection:
    return SchedulerPlaceSelection(
        content_id=content_id,
        title=content_id,
        category=category,
        latitude=37.5,
        longitude=127.0,
    )


def test_plans_travel_and_visits_from_exact_start_datetime() -> None:
    start = datetime(2026, 9, 1, 9, 0, tzinfo=timezone.utc)
    end = datetime(2026, 9, 1, 18, 0, tzinfo=timezone.utc)

    planned = plan_schedule(
        [
            selection("restaurant", PlaceCategory.RESTAURANT),
            selection("cafe", PlaceCategory.CAFE),
        ],
        [RouteLeg(600, 1_000), RouteLeg(300, 500)],
        start_datetime=start,
        end_datetime=end,
    )

    assert planned[0].scheduled_start_datetime.isoformat() == "2026-09-01T11:30:00+00:00"
    assert planned[0].scheduled_end_datetime.isoformat() == "2026-09-01T12:30:00+00:00"
    assert planned[0].schedule_role == ScheduleRole.MEAL
    assert planned[0].time_slot == TimeSlot.LUNCH
    assert planned[1].scheduled_start_datetime.isoformat() == "2026-09-01T12:35:00+00:00"
    assert planned[1].scheduled_end_datetime.isoformat() == "2026-09-01T13:20:00+00:00"
    assert planned[1].schedule_role == ScheduleRole.GENERAL_VISIT
    assert [place.visit_order for place in planned] == [1, 2]


def test_rejects_plan_that_exceeds_exact_end_datetime() -> None:
    start = datetime(2026, 9, 1, 9, 0, tzinfo=timezone.utc)
    with pytest.raises(ScheduleWindowError, match="일정 범위를 초과"):
        plan_schedule(
            [selection("festival", PlaceCategory.FESTIVAL)],
            [RouteLeg(600, 1_000)],
            start_datetime=start,
            end_datetime=datetime(2026, 9, 1, 10, 0, tzinfo=timezone.utc),
        )


def test_multi_day_plan_pauses_until_next_daily_active_window() -> None:
    planned = plan_schedule(
        [
            selection("festival-1", PlaceCategory.FESTIVAL),
            selection("festival-2", PlaceCategory.FESTIVAL),
        ],
        [RouteLeg(0, 0), RouteLeg(0, 0)],
        start_datetime=datetime(2026, 9, 1, 18, 0, tzinfo=timezone.utc),
        end_datetime=datetime(2026, 9, 2, 18, 0, tzinfo=timezone.utc),
    )

    assert planned[0].scheduled_start_datetime.isoformat() == "2026-09-01T18:00:00+00:00"
    assert planned[0].scheduled_end_datetime.isoformat() == "2026-09-01T20:00:00+00:00"
    assert planned[1].scheduled_start_datetime.isoformat() == "2026-09-02T09:00:00+00:00"
    assert planned[1].scheduled_end_datetime.isoformat() == "2026-09-02T11:00:00+00:00"
    assert [place.day_no for place in planned] == [1, 2]
    assert [place.visit_order for place in planned] == [1, 1]


def test_visit_may_end_exactly_at_requested_end_datetime() -> None:
    start = datetime(2026, 9, 1, 9, 0, tzinfo=timezone.utc)
    end = datetime(2026, 9, 1, 10, 0, tzinfo=timezone.utc)

    planned = plan_schedule(
        [selection("restaurant", PlaceCategory.RESTAURANT)],
        [RouteLeg(0, 0)],
        start_datetime=start,
        end_datetime=end,
    )

    assert planned[0].scheduled_start_datetime == start
    assert planned[0].scheduled_end_datetime == end


def test_excess_restaurant_becomes_snack_after_available_meal_windows() -> None:
    start = datetime(2026, 9, 1, 9, 0, tzinfo=timezone.utc)
    planned = plan_schedule(
        [selection(f"restaurant-{index}", PlaceCategory.RESTAURANT) for index in range(4)],
        [RouteLeg(0, 0) for _ in range(4)],
        start_datetime=start,
        end_datetime=datetime(2026, 9, 1, 20, 0, tzinfo=timezone.utc),
    )

    assert [stop.schedule_role for stop in planned] == [
        ScheduleRole.MEAL,
        ScheduleRole.MEAL,
        ScheduleRole.MEAL,
        ScheduleRole.SNACK,
    ]
    assert [stop.time_slot for stop in planned[:3]] == [
        TimeSlot.MORNING,
        TimeSlot.LUNCH,
        TimeSlot.DINNER,
    ]
    assert planned[-1].scheduled_end_datetime - planned[-1].scheduled_start_datetime == timedelta(
        minutes=45
    )


def test_accommodation_uses_first_day_check_in_and_last_day_check_out() -> None:
    planned = plan_schedule(
        [selection("hotel", PlaceCategory.ACCOMMODATION)],
        [RouteLeg(0, 0)],
        start_datetime=datetime(2026, 9, 1, 9, 0, tzinfo=timezone.utc),
        end_datetime=datetime(2026, 9, 3, 20, 0, tzinfo=timezone.utc),
    )

    stay = planned[0]
    assert stay.schedule_role == ScheduleRole.ACCOMMODATION
    assert stay.check_in_datetime.isoformat() == "2026-09-01T15:00:00+00:00"
    assert stay.scheduled_end_datetime.isoformat() == "2026-09-01T15:30:00+00:00"
    assert stay.check_out_datetime.isoformat() == "2026-09-03T11:00:00+00:00"


def test_final_day_visits_start_after_accommodation_check_out() -> None:
    planned = plan_schedule(
        [
            selection("hotel", PlaceCategory.ACCOMMODATION),
            selection("long-course", PlaceCategory.TRAVEL_COURSE),
            selection("final-cafe", PlaceCategory.CAFE),
        ],
        [RouteLeg(0, 0), RouteLeg(0, 0), RouteLeg(0, 0)],
        start_datetime=datetime(2026, 9, 1, 19, 0, tzinfo=timezone.utc),
        end_datetime=datetime(2026, 9, 2, 20, 0, tzinfo=timezone.utc),
    )

    final_day_stops = [stop for stop in planned if stop.day_no == 2]
    assert final_day_stops
    assert all(
        stop.scheduled_start_datetime
        >= datetime(2026, 9, 2, 11, 0, tzinfo=timezone.utc)
        for stop in final_day_stops
    )


def test_two_accommodations_cover_two_consecutive_nights() -> None:
    planned = plan_schedule(
        [
            selection("hotel-night-1", PlaceCategory.ACCOMMODATION),
            selection("hotel-night-2", PlaceCategory.ACCOMMODATION),
        ],
        [RouteLeg(0, 0), RouteLeg(0, 0)],
        start_datetime=datetime(2026, 9, 1, 9, 0, tzinfo=timezone.utc),
        end_datetime=datetime(2026, 9, 3, 20, 0, tzinfo=timezone.utc),
    )

    assert [stay.check_in_datetime.isoformat() for stay in planned] == [
        "2026-09-01T15:00:00+00:00",
        "2026-09-02T15:00:00+00:00",
    ]
    assert [stay.check_out_datetime.isoformat() for stay in planned] == [
        "2026-09-02T11:00:00+00:00",
        "2026-09-03T11:00:00+00:00",
    ]
    assert [stay.day_no for stay in planned] == [1, 2]
