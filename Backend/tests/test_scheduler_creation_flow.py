import os
import unittest
from types import SimpleNamespace

os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("GOOGLE_CLIENT_ID", "test.apps.googleusercontent.com")
os.environ.setdefault("KAKAO_APP_ID", "1234")
os.environ.setdefault("JWT_SECRET_KEY", "test-only-secret-key-with-32-characters")

from fastapi import FastAPI
from fastapi.testclient import TestClient
from sqlalchemy import create_engine, event, func, select
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from api.guestbook.models import Guestbook  # noqa: F401 - register all FK tables
from api.place.models import MemoryPlace, Place
from api.scheduler.models import MobilityMode, Scheduler, SchedulerPlace
from api.scheduler.route_optimizer import RoutePoint
from api.scheduler.router import get_route_verifier
from api.scheduler.router import router as scheduler_router
from api.scheduler.schemas import SchedulerCreateRequest
from api.scheduler.service import SchedulerService
from core.database import Base
from core.dependencies import get_current_user, get_db
from infra.kakao_route import KakaoRouteError, RouteLeg


def scheduler_payload() -> dict[str, object]:
    return {
        "title": "추억 여행",
        "mobility_mode": "WALK",
        "search_radius": 3,
        "trip_type": "DAY_TRIP",
        "memory_place": {
            "name": "내가 다니던 학교",
            "address": "서울특별시 중구 세종대로 1",
            "latitude": 37.5665,
            "longitude": 126.978,
        },
        "places": [
            {
                "content_id": "tour-restaurant-1",
                "title": "오래된 냉면집",
                "category": "restaurant",
                "latitude": 37.567,
                "longitude": 126.979,
                "image_url": "https://example.com/restaurant.jpg",
                "kakao_place_id": "kakao-restaurant-1",
                "place_url": "http://place.map.kakao.com/kakao-restaurant-1",
            },
            {
                "content_id": "tour-cafe-1",
                "title": "추억의 다방",
                "category": "cafe",
                "latitude": 37.568,
                "longitude": 126.98,
                "image_url": None,
                "kakao_place_id": "kakao-cafe-1",
                "place_url": "https://place.map.kakao.com/kakao-cafe-1",
            },
        ],
        "companion_type": "FRIEND",
        "companion_count": 2,
        "start_datetime": "2026-09-01T09:00:00+09:00",
        "end_datetime": "2026-09-01T18:00:00+09:00",
    }


class SchedulerCreationFlowTests(unittest.TestCase):
    def setUp(self) -> None:
        self.engine = create_engine(
            "sqlite://",
            connect_args={"check_same_thread": False},
            poolclass=StaticPool,
        )
        Base.metadata.create_all(self.engine)
        app = FastAPI()
        app.include_router(scheduler_router, prefix="/api/v1")

        def override_db():
            with Session(self.engine) as db:
                yield db

        app.dependency_overrides[get_db] = override_db
        app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(id=77)
        self.client = TestClient(app)
        self.app = app

    def tearDown(self) -> None:
        self.client.close()
        self.engine.dispose()

    def test_creates_memory_place_scheduler_and_selected_places_at_once(self) -> None:
        response = self.client.post("/api/v1/schedulers", json=scheduler_payload())

        self.assertEqual(response.status_code, 201)
        body = response.json()
        self.assertEqual(body["memory_place"]["name"], "내가 다니던 학교")
        self.assertEqual(len(body["places"]), 2)
        restaurant = next(
            place
            for place in body["places"]
            if place["place"]["content_id"] == "tour-restaurant-1"
        )
        self.assertEqual(restaurant["place"]["title"], "오래된 냉면집")
        self.assertEqual(
            restaurant["place"]["place_url"],
            "https://place.map.kakao.com/kakao-restaurant-1",
        )
        self.assertFalse(body["route_verified"])
        self.assertGreaterEqual(
            body["places"][0]["scheduled_start_datetime"],
            body["start_datetime"],
        )
        self.assertLessEqual(
            body["places"][-1]["scheduled_end_datetime"],
            body["end_datetime"],
        )

        with Session(self.engine) as db:
            self.assertEqual(db.scalar(select(func.count(Scheduler.id))), 1)
            self.assertEqual(db.scalar(select(func.count(MemoryPlace.id))), 1)
            self.assertEqual(db.scalar(select(func.count(Place.id))), 2)
            self.assertEqual(db.scalar(select(func.count(SchedulerPlace.id))), 2)

    def test_legacy_frontend_order_is_accepted_and_replaced_by_server_plan(
        self,
    ) -> None:
        payload = scheduler_payload()
        payload["places"] = [
            {
                "place": place,
                "day_no": 9,
                "time_slot": "NIGHT",
                "visit_order": 99,
            }
            for place in payload["places"]
        ]

        response = self.client.post("/api/v1/schedulers", json=payload)

        self.assertEqual(response.status_code, 201)
        self.assertTrue(
            all(place["day_no"] == 1 for place in response.json()["places"])
        )
        self.assertEqual(
            [place["visit_order"] for place in response.json()["places"]],
            [1, 2],
        )

    def test_kakao_verification_runs_once_before_any_write(self) -> None:
        engine = self.engine

        class InspectingVerifier:
            calls = 0

            def verify(
                self,
                mobility_mode: MobilityMode,
                route: tuple[RoutePoint, ...],
            ) -> tuple[RouteLeg, ...]:
                self.calls += 1
                assert mobility_mode == MobilityMode.WALK
                with Session(engine) as db:
                    assert db.scalar(select(func.count(Scheduler.id))) == 0
                    assert db.scalar(select(func.count(MemoryPlace.id))) == 0
                    assert db.scalar(select(func.count(Place.id))) == 0
                return tuple(RouteLeg(60, 100) for _ in route[1:])

        verifier = InspectingVerifier()
        self.app.dependency_overrides[get_route_verifier] = lambda: verifier

        response = self.client.post("/api/v1/schedulers", json=scheduler_payload())

        self.assertEqual(response.status_code, 201)
        self.assertEqual(verifier.calls, 1)
        self.assertTrue(response.json()["route_verified"])
        self.assertEqual(
            response.json()["places"][0]["travel_seconds_from_previous"],
            60,
        )

    def test_kakao_failure_falls_back_to_local_route(self) -> None:
        class FailingVerifier:
            calls = 0

            def verify(self, mobility_mode, route):
                del mobility_mode, route
                self.calls += 1
                raise KakaoRouteError("temporary outage")

        verifier = FailingVerifier()
        self.app.dependency_overrides[get_route_verifier] = lambda: verifier

        response = self.client.post("/api/v1/schedulers", json=scheduler_payload())

        self.assertEqual(response.status_code, 201)
        self.assertEqual(verifier.calls, 1)
        self.assertFalse(response.json()["route_verified"])

    def test_rejects_too_small_window_without_persisting_anything(self) -> None:
        payload = scheduler_payload()
        payload["end_datetime"] = "2026-09-01T09:30:00+09:00"

        response = self.client.post("/api/v1/schedulers", json=payload)

        self.assertEqual(response.status_code, 422)
        with Session(self.engine) as db:
            self.assertEqual(db.scalar(select(func.count(Scheduler.id))), 0)
            self.assertEqual(db.scalar(select(func.count(MemoryPlace.id))), 0)
            self.assertEqual(db.scalar(select(func.count(Place.id))), 0)

    def test_reuses_and_updates_place_by_tour_content_id(self) -> None:
        first = self.client.post("/api/v1/schedulers", json=scheduler_payload())
        self.assertEqual(first.status_code, 201)

        second_payload = scheduler_payload()
        selected = second_payload["places"][0]
        selected = {
            **selected,
            "title": "상호가 바뀐 냉면집",
            "kakao_place_id": "kakao-restaurant-new",
            "place_url": "https://place.map.kakao.com/kakao-restaurant-new",
        }
        second_payload["places"] = [selected]
        second = self.client.post("/api/v1/schedulers", json=second_payload)

        self.assertEqual(second.status_code, 201)
        with Session(self.engine) as db:
            matching_places = db.scalars(
                select(Place).where(Place.api_place_id == "tour-restaurant-1")
            ).all()
            self.assertEqual(len(matching_places), 1)
            self.assertEqual(matching_places[0].name, "상호가 바뀐 냉면집")
            self.assertEqual(
                matching_places[0].kakao_place_url,
                "https://place.map.kakao.com/kakao-restaurant-new",
            )

    def test_creates_scheduler_when_kakao_link_is_unavailable(self) -> None:
        payload = scheduler_payload()
        selected = payload["places"][0]
        selected = {
            key: value
            for key, value in selected.items()
            if key not in {"kakao_place_id", "place_url"}
        }
        payload["places"] = [selected]

        response = self.client.post("/api/v1/schedulers", json=payload)

        self.assertEqual(response.status_code, 201)
        stored_place = response.json()["places"][0]["place"]
        self.assertIsNone(stored_place["kakao_place_id"])
        self.assertIsNone(stored_place["place_url"])

    def test_null_kakao_link_does_not_erase_existing_place_link(self) -> None:
        first = self.client.post("/api/v1/schedulers", json=scheduler_payload())
        self.assertEqual(first.status_code, 201)

        payload = scheduler_payload()
        selected = payload["places"][0]
        selected = {
            **selected,
            "kakao_place_id": None,
            "place_url": None,
        }
        payload["places"] = [selected]

        response = self.client.post("/api/v1/schedulers", json=payload)

        self.assertEqual(response.status_code, 201)
        stored_place = response.json()["places"][0]["place"]
        self.assertEqual(stored_place["kakao_place_id"], "kakao-restaurant-1")
        self.assertEqual(
            stored_place["place_url"],
            "https://place.map.kakao.com/kakao-restaurant-1",
        )

    def test_full_read_edit_and_delete_flow(self) -> None:
        created = self.client.post("/api/v1/schedulers", json=scheduler_payload())
        scheduler_id = created.json()["id"]
        scheduler_place_id = created.json()["places"][0]["id"]

        listed = self.client.get("/api/v1/schedulers")
        detailed = self.client.get(f"/api/v1/schedulers/{scheduler_id}")
        updated = self.client.patch(
            f"/api/v1/schedulers/{scheduler_id}/places/{scheduler_place_id}",
            json={
                "scheduled_start_datetime": "2026-09-01T15:00:00+09:00",
                "scheduled_end_datetime": "2026-09-01T16:00:00+09:00",
            },
        )
        removed = self.client.delete(
            f"/api/v1/schedulers/{scheduler_id}/places/{scheduler_place_id}"
        )
        deleted = self.client.delete(f"/api/v1/schedulers/{scheduler_id}")
        missing = self.client.get(f"/api/v1/schedulers/{scheduler_id}")

        self.assertEqual(listed.status_code, 200)
        self.assertEqual(len(listed.json()), 1)
        self.assertEqual(detailed.status_code, 200)
        self.assertEqual(updated.status_code, 200)
        self.assertEqual(updated.json()["time_slot"], "AFTERNOON")
        self.assertEqual(removed.status_code, 204)
        self.assertEqual(deleted.status_code, 204)
        self.assertEqual(missing.status_code, 404)

    def test_rolls_back_the_entire_creation_when_a_place_link_fails(self) -> None:
        with Session(self.engine) as db:
            service = SchedulerService(db)

            def fail_scheduler_place_flush(session, flush_context, instances):
                del flush_context, instances
                if any(isinstance(item, SchedulerPlace) for item in session.new):
                    raise RuntimeError("scheduler place insert failed")

            event.listen(db, "before_flush", fail_scheduler_place_flush)
            try:
                with self.assertRaisesRegex(
                    RuntimeError, "scheduler place insert failed"
                ):
                    service.create(
                        user_id=77,
                        request=SchedulerCreateRequest.model_validate(
                            scheduler_payload()
                        ),
                    )
            finally:
                event.remove(db, "before_flush", fail_scheduler_place_flush)

            self.assertEqual(db.scalar(select(func.count(Scheduler.id))), 0)
            self.assertEqual(db.scalar(select(func.count(MemoryPlace.id))), 0)
            self.assertEqual(db.scalar(select(func.count(Place.id))), 0)
            self.assertEqual(db.scalar(select(func.count(SchedulerPlace.id))), 0)


if __name__ == "__main__":
    unittest.main()
