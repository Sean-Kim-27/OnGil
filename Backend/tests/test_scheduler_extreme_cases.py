import os
from datetime import datetime
from types import SimpleNamespace

os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("GOOGLE_CLIENT_ID", "test.apps.googleusercontent.com")
os.environ.setdefault("KAKAO_APP_ID", "1234")
os.environ.setdefault("JWT_SECRET_KEY", "test-only-secret-key-with-32-characters")

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, func, select
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from api.place.models import MemoryPlace, Place
from api.scheduler.models import MobilityMode, Scheduler, SchedulerPlace
from api.scheduler.route_optimizer import RoutePoint
from api.scheduler.router import get_route_verifier
from api.scheduler.router import router as scheduler_router
from core.database import Base
from core.dependencies import get_current_user, get_db
from infra.kakao_route import RouteLeg


class CountingRouteVerifier:
    def __init__(self, *, leg_seconds: int = 300, leg_distance_m: int = 500) -> None:
        self.leg_seconds = leg_seconds
        self.leg_distance_m = leg_distance_m
        self.calls = 0
        self.routes: list[tuple[RoutePoint, ...]] = []

    def verify(
        self,
        mobility_mode: MobilityMode,
        route: tuple[RoutePoint, ...],
    ) -> tuple[RouteLeg, ...]:
        del mobility_mode
        self.calls += 1
        self.routes.append(route)
        return tuple(RouteLeg(self.leg_seconds, self.leg_distance_m) for _ in route[1:])


def selected_place(index: int, category: str) -> dict[str, object]:
    return {
        "content_id": f"extreme-{category}-{index}",
        "title": f"극단 테스트 장소 {index}",
        "category": category,
        "latitude": 37.45 + index * 0.002,
        "longitude": 126.90 + index * 0.002,
    }


def scheduler_payload(
    places: list[dict[str, object]],
    *,
    mobility_mode: str = "CAR",
    start_datetime: str = "2026-09-01T09:00:00+09:00",
    end_datetime: str = "2026-09-02T20:00:00+09:00",
) -> dict[str, object]:
    return {
        "title": "극단 일정 검증",
        "mobility_mode": mobility_mode,
        "search_radius": 5,
        "trip_type": "OVERNIGHT",
        "memory_place": {
            "name": "출발 기준점",
            "latitude": 37.44,
            "longitude": 126.89,
        },
        "places": places,
        "companion_type": "FAMILY",
        "companion_count": 20,
        "start_datetime": start_datetime,
        "end_datetime": end_datetime,
    }


class TestSchedulerExtremeCases:
    def setup_method(self) -> None:
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        self.verifier = CountingRouteVerifier()
        app = FastAPI()
        app.include_router(scheduler_router, prefix="/api/v1")

        def override_db():
            with Session(self.engine) as db:
                yield db

        app.dependency_overrides[get_db] = override_db
        app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(id=88)
        app.dependency_overrides[get_route_verifier] = lambda: self.verifier
        self.client = TestClient(app)

    def teardown_method(self) -> None:
        self.client.close()
        self.engine.dispose()

    def test_one_night_two_days_with_five_meals_and_eight_cafes(self) -> None:
        places = [selected_place(index, "restaurant") for index in range(5)]
        places.extend(selected_place(index + 5, "cafe") for index in range(8))

        response = self.client.post(
            "/api/v1/schedulers",
            json=scheduler_payload(places),
        )

        assert response.status_code == 201
        body = response.json()
        stored_places = body["places"]
        assert self.verifier.calls == 1
        assert len(self.verifier.routes[0]) == 14  # anchor + 13 selected places
        assert len(stored_places) == 13
        assert len({place["place"]["content_id"] for place in stored_places}) == 13
        assert (
            sum(place["place"]["category"] == "restaurant" for place in stored_places)
            == 5
        )
        assert sum(place["place"]["category"] == "cafe" for place in stored_places) == 8
        assert sum(place["schedule_role"] == "MEAL" for place in stored_places) == 5
        assert all(
            _inside_meal_window(place)
            for place in stored_places
            if place["schedule_role"] == "MEAL"
        )
        assert {place["day_no"] for place in stored_places} == {1, 2}
        _assert_schedule_invariants(body)

    def test_accommodation_is_fixed_to_check_in_and_check_out_preferences(self) -> None:
        places = [
            selected_place(0, "tourist_attraction"),
            selected_place(1, "restaurant"),
            selected_place(2, "accommodation"),
            selected_place(3, "cafe"),
        ]

        response = self.client.post(
            "/api/v1/schedulers",
            json=scheduler_payload(places),
        )

        assert response.status_code == 201
        assert self.verifier.calls == 1
        stay = next(
            place
            for place in response.json()["places"]
            if place["schedule_role"] == "ACCOMMODATION"
        )
        check_in = datetime.fromisoformat(stay["check_in_datetime"])
        check_out = datetime.fromisoformat(stay["check_out_datetime"])
        assert check_in.date().isoformat() == "2026-09-01"
        assert 15 <= check_in.hour <= 16
        assert check_out.isoformat() == "2026-09-02T11:00:00"

    def test_two_nights_three_days_allows_two_different_accommodations(self) -> None:
        places = [
            selected_place(0, "tourist_attraction"),
            selected_place(1, "accommodation"),
            selected_place(2, "restaurant"),
            selected_place(3, "accommodation"),
            selected_place(4, "cafe"),
        ]

        response = self.client.post(
            "/api/v1/schedulers",
            json=scheduler_payload(
                places,
                start_datetime="2026-09-01T09:00:00+09:00",
                end_datetime="2026-09-03T20:00:00+09:00",
            ),
        )

        assert response.status_code == 201
        stays = sorted(
            (
                place
                for place in response.json()["places"]
                if place["schedule_role"] == "ACCOMMODATION"
            ),
            key=lambda place: place["check_in_datetime"],
        )
        assert len(stays) == 2
        assert [
            datetime.fromisoformat(stay["check_in_datetime"]).day for stay in stays
        ] == [
            1,
            2,
        ]
        assert [
            datetime.fromisoformat(stay["check_in_datetime"]).hour for stay in stays
        ] == [
            15,
            15,
        ]
        assert [
            datetime.fromisoformat(stay["check_out_datetime"]).day for stay in stays
        ] == [
            2,
            3,
        ]
        assert [
            datetime.fromisoformat(stay["check_out_datetime"]).hour for stay in stays
        ] == [
            11,
            11,
        ]
        assert self.verifier.calls == 1
        _assert_schedule_invariants(response.json())

    def test_replaces_stay_ranges_and_reverses_accommodation_order(self) -> None:
        hotel_a = selected_place(1, "accommodation")
        hotel_b = selected_place(2, "accommodation")
        created = self.client.post(
            "/api/v1/schedulers",
            json=scheduler_payload(
                [hotel_a, selected_place(3, "cafe"), hotel_b],
                start_datetime="2026-09-01T09:00:00+09:00",
                end_datetime="2026-09-04T20:00:00+09:00",
            ),
        )

        assert created.status_code == 201
        scheduler_id = created.json()["id"]
        stays_by_content_id = {
            place["place"]["content_id"]: place
            for place in created.json()["places"]
            if place["schedule_role"] == "ACCOMMODATION"
        }
        hotel_a_id = stays_by_content_id[hotel_a["content_id"]]["id"]
        hotel_b_id = stays_by_content_id[hotel_b["content_id"]]["id"]

        replaced = self.client.put(
            f"/api/v1/schedulers/{scheduler_id}/stays",
            json={
                "stays": [
                    {
                        "scheduler_place_id": hotel_b_id,
                        "check_in_date": "2026-09-01",
                        "check_out_date": "2026-09-03",
                    },
                    {
                        "scheduler_place_id": hotel_a_id,
                        "check_in_date": "2026-09-03",
                        "check_out_date": "2026-09-04",
                    },
                ]
            },
        )

        assert replaced.status_code == 200, replaced.text
        stays = sorted(
            (
                place
                for place in replaced.json()["places"]
                if place["schedule_role"] == "ACCOMMODATION"
            ),
            key=lambda place: place["check_in_datetime"],
        )
        assert [stay["place"]["content_id"] for stay in stays] == [
            hotel_b["content_id"],
            hotel_a["content_id"],
        ]
        assert [stay["check_in_datetime"][:10] for stay in stays] == [
            "2026-09-01",
            "2026-09-03",
        ]
        assert [stay["check_out_datetime"][:10] for stay in stays] == [
            "2026-09-03",
            "2026-09-04",
        ]
        assert self.verifier.calls == 2  # 생성 1회 + 숙박 수정 1회
        _assert_schedule_invariants(replaced.json())

    def test_rejects_gapped_stay_replacement_without_calling_kakao(self) -> None:
        hotel_a = selected_place(1, "accommodation")
        hotel_b = selected_place(2, "accommodation")
        created = self.client.post(
            "/api/v1/schedulers",
            json=scheduler_payload(
                [hotel_a, hotel_b],
                end_datetime="2026-09-04T20:00:00+09:00",
            ),
        )
        assert created.status_code == 201
        scheduler_id = created.json()["id"]
        stay_ids = [place["id"] for place in created.json()["places"]]
        original_ranges = [
            (place["check_in_datetime"], place["check_out_datetime"])
            for place in created.json()["places"]
        ]

        rejected = self.client.put(
            f"/api/v1/schedulers/{scheduler_id}/stays",
            json={
                "stays": [
                    {
                        "scheduler_place_id": stay_ids[0],
                        "check_in_date": "2026-09-01",
                        "check_out_date": "2026-09-02",
                    },
                    {
                        "scheduler_place_id": stay_ids[1],
                        "check_in_date": "2026-09-03",
                        "check_out_date": "2026-09-04",
                    },
                ]
            },
        )
        unchanged = self.client.get(f"/api/v1/schedulers/{scheduler_id}")

        assert rejected.status_code == 422
        assert "비거나 겹치지 않게" in rejected.json()["detail"]
        assert self.verifier.calls == 1
        assert [
            (place["check_in_datetime"], place["check_out_datetime"])
            for place in unchanged.json()["places"]
        ] == original_ranges

    def test_one_night_two_days_rejects_two_accommodations_without_side_effects(
        self,
    ) -> None:
        response = self.client.post(
            "/api/v1/schedulers",
            json=scheduler_payload(
                [
                    selected_place(0, "accommodation"),
                    selected_place(1, "accommodation"),
                ]
            ),
        )

        assert response.status_code == 422
        assert "1박" in str(response.json())
        assert self.verifier.calls == 0
        self._assert_database_empty()

    def test_two_nights_three_days_rejects_three_accommodations(self) -> None:
        response = self.client.post(
            "/api/v1/schedulers",
            json=scheduler_payload(
                [selected_place(index, "accommodation") for index in range(3)],
                end_datetime="2026-09-03T20:00:00+09:00",
            ),
        )

        assert response.status_code == 422
        assert "2박" in str(response.json())
        assert self.verifier.calls == 0
        self._assert_database_empty()

    def test_seven_nights_allows_seven_different_accommodations(self) -> None:
        response = self.client.post(
            "/api/v1/schedulers",
            json=scheduler_payload(
                [selected_place(index, "accommodation") for index in range(7)],
                end_datetime="2026-09-08T20:00:00+09:00",
            ),
        )

        assert response.status_code == 201
        stays = sorted(
            response.json()["places"],
            key=lambda place: place["check_in_datetime"],
        )
        assert len(stays) == 7
        assert [
            datetime.fromisoformat(stay["check_in_datetime"]).day for stay in stays
        ] == list(range(1, 8))
        assert [
            datetime.fromisoformat(stay["check_out_datetime"]).day for stay in stays
        ] == list(range(2, 9))
        assert all(
            datetime.fromisoformat(stay["check_in_datetime"]).hour == 15
            for stay in stays
        )
        assert all(
            datetime.fromisoformat(stay["check_out_datetime"]).hour == 11
            for stay in stays
        )
        assert self.verifier.calls == 1
        _assert_schedule_invariants(response.json())

    def test_excess_restaurants_are_saved_as_snacks(self) -> None:
        places = [selected_place(index, "restaurant") for index in range(7)]

        response = self.client.post(
            "/api/v1/schedulers",
            json=scheduler_payload(
                places,
                end_datetime="2026-09-02T21:00:00+09:00",
            ),
        )

        assert response.status_code == 201
        roles = [place["schedule_role"] for place in response.json()["places"]]
        assert roles.count("MEAL") == 5
        assert roles.count("SNACK") == 2
        assert self.verifier.calls == 1

    def test_seven_nights_eight_days_with_maximum_car_places(self) -> None:
        self.verifier.leg_seconds = 1_800
        places = [
            selected_place(index, "festival" if index % 2 == 0 else "travel_course")
            for index in range(31)
        ]

        response = self.client.post(
            "/api/v1/schedulers",
            json=scheduler_payload(
                places,
                start_datetime="2026-09-01T09:00:00+09:00",
                end_datetime="2026-09-08T20:00:00+09:00",
            ),
        )

        assert response.status_code == 201
        body = response.json()
        assert self.verifier.calls == 1
        assert len(self.verifier.routes[0]) == 32  # anchor + 31 selected places
        assert len(body["places"]) == 31
        assert {place["day_no"] for place in body["places"]} == set(range(1, 9))
        _assert_schedule_invariants(body)

        with Session(self.engine) as db:
            assert db.scalar(select(func.count(Scheduler.id))) == 1
            assert db.scalar(select(func.count(MemoryPlace.id))) == 1
            assert db.scalar(select(func.count(Place.id))) == 31
            assert db.scalar(select(func.count(SchedulerPlace.id))) == 31

    def test_rejects_more_than_kakao_one_call_limits_without_writes(self) -> None:
        cases = [
            ("WALK", 7),
            ("CAR", 32),
        ]
        for mobility_mode, place_count in cases:
            response = self.client.post(
                "/api/v1/schedulers",
                json=scheduler_payload(
                    [selected_place(index, "cafe") for index in range(place_count)],
                    mobility_mode=mobility_mode,
                    end_datetime="2026-09-08T20:00:00+09:00",
                ),
            )

            assert response.status_code == 422

        assert self.verifier.calls == 0
        self._assert_database_empty()

    def test_walk_boundary_of_six_places_still_uses_one_call(self) -> None:
        response = self.client.post(
            "/api/v1/schedulers",
            json=scheduler_payload(
                [selected_place(index, "cafe") for index in range(6)],
                mobility_mode="WALK",
            ),
        )

        assert response.status_code == 201
        assert self.verifier.calls == 1
        assert len(self.verifier.routes[0]) == 7  # anchor + 6 selected places
        assert len(response.json()["places"]) == 6
        _assert_schedule_invariants(response.json())

    def test_impossible_visit_time_is_rejected_before_kakao_call(self) -> None:
        places = [selected_place(index, "restaurant") for index in range(5)]
        places.extend(selected_place(index + 5, "cafe") for index in range(8))

        response = self.client.post(
            "/api/v1/schedulers",
            json=scheduler_payload(
                places,
                end_datetime="2026-09-01T12:00:00+09:00",
            ),
        )

        assert response.status_code == 422
        assert "최소 체류시간" in response.json()["detail"]
        assert self.verifier.calls == 0
        self._assert_database_empty()

    def _assert_database_empty(self) -> None:
        with Session(self.engine) as db:
            assert db.scalar(select(func.count(Scheduler.id))) == 0
            assert db.scalar(select(func.count(MemoryPlace.id))) == 0
            assert db.scalar(select(func.count(Place.id))) == 0
            assert db.scalar(select(func.count(SchedulerPlace.id))) == 0


def _assert_schedule_invariants(body: dict[str, object]) -> None:
    start = datetime.fromisoformat(body["start_datetime"])
    end = datetime.fromisoformat(body["end_datetime"])
    previous_end = start

    for place in body["places"]:
        scheduled_start = datetime.fromisoformat(place["scheduled_start_datetime"])
        scheduled_end = datetime.fromisoformat(place["scheduled_end_datetime"])
        assert start <= scheduled_start < scheduled_end <= end
        assert scheduled_start >= previous_end
        assert place["travel_seconds_from_previous"] >= 0
        assert place["travel_distance_m"] >= 0
        previous_end = scheduled_end


def _inside_meal_window(place: dict[str, object]) -> bool:
    start = datetime.fromisoformat(place["scheduled_start_datetime"])
    end = datetime.fromisoformat(place["scheduled_end_datetime"])
    windows = {
        "MORNING": ((7, 30), (10, 0)),
        "LUNCH": ((11, 30), (14, 0)),
        "DINNER": ((17, 30), (20, 30)),
    }
    window_start, window_end = windows[place["time_slot"]]
    start_minutes = start.hour * 60 + start.minute
    end_minutes = end.hour * 60 + end.minute
    return (
        window_start[0] * 60 + window_start[1] <= start_minutes
        and end_minutes <= window_end[0] * 60 + window_end[1]
    )
