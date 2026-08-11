import os
import unittest
from datetime import datetime, timezone

os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("GOOGLE_CLIENT_ID", "test.apps.googleusercontent.com")
os.environ.setdefault("KAKAO_APP_ID", "1234")
os.environ.setdefault("JWT_SECRET_KEY", "test-only-secret-key-with-32-characters")

import sys
sys.path.insert(0, "src")

from sqlalchemy import create_engine, select
from sqlalchemy.orm import Session
from sqlalchemy.pool import StaticPool

from core.database import Base
from api.place.models import MemoryPlace, Place
from api.place.schemas import PlaceCategory
from api.scheduler.models import CompanionType, MobilityMode, TripType
from api.scheduler.schemas import (
    SchedulerCreateRequest,
    SchedulerPlaceCreateRequest,
    SchedulerPlaceSelection,
)
from api.scheduler.service import SchedulerService


def make_session():
    engine = create_engine(
        "sqlite://", connect_args={"check_same_thread": False}, poolclass=StaticPool
    )
    Base.metadata.create_all(engine)
    return Session(engine)


def make_scheduler(service: SchedulerService, memory_place_id: int | None = None):
    return service.create(
        user_id=1,
        request=SchedulerCreateRequest(
            title="추억 여행",
            mobility_mode=MobilityMode.WALK,
            search_radius=4,
            trip_type=TripType.DAY_TRIP,
            memory_place_id=memory_place_id,
            companion_type=CompanionType.FAMILY,
            companion_count=3,
            start_datetime=datetime(2026, 9, 1, 9, 0, tzinfo=timezone.utc),
            end_datetime=datetime(2026, 9, 1, 18, 0, tzinfo=timezone.utc),
        ),
    )


class GetOrCreatePlaceTests(unittest.TestCase):
    def test_new_content_id_creates_a_place_row(self):
        db = make_session()
        service = SchedulerService(db)
        scheduler = make_scheduler(service)

        self.assertEqual(db.scalar(select(Place).where(Place.id.isnot(None))), None)

        request = SchedulerPlaceCreateRequest(
            place=SchedulerPlaceSelection(
                content_id="tour-111",
                title="오래된 냉면집",
                category=PlaceCategory.RESTAURANT,
                latitude=37.51,
                longitude=127.01,
                image_url="https://example.com/img.jpg",
            ),
            day_no=1,
            visit_order=1,
        )
        scheduler_place = service.add_place(1, scheduler.id, request)

        # scheduler_places.place_id는 content_id 문자열이 아니라
        # 내부 Place PK(정수)를 가리켜야 한다.
        self.assertIsInstance(scheduler_place.place_id, int)

        created_place = db.get(Place, scheduler_place.place_id)
        self.assertIsNotNone(created_place)
        self.assertEqual(created_place.api_place_id, "tour-111")
        self.assertEqual(created_place.name, "오래된 냉면집")
        self.assertEqual(created_place.category, "restaurant")
        db.close()

    def test_same_content_id_reuses_existing_place_instead_of_duplicating(self):
        db = make_session()
        service = SchedulerService(db)
        scheduler = make_scheduler(service)

        selection = SchedulerPlaceSelection(
            content_id="tour-222",
            title="신상 카페",
            category=PlaceCategory.CAFE,
            latitude=37.52,
            longitude=127.02,
        )

        first = service.add_place(
            1,
            scheduler.id,
            SchedulerPlaceCreateRequest(place=selection, day_no=1, visit_order=1),
        )
        second = service.add_place(
            1,
            scheduler.id,
            SchedulerPlaceCreateRequest(place=selection, day_no=2, visit_order=1),
        )

        # 같은 content_id로 두 번 추가해도 Place 레코드는 하나만 생성되어야 함
        self.assertEqual(first.place_id, second.place_id)
        all_places = db.scalars(
            select(Place).where(Place.api_place_id == "tour-222")
        ).all()
        self.assertEqual(len(all_places), 1)
        db.close()

    def test_add_place_to_missing_scheduler_raises(self):
        from api.scheduler.service import SchedulerNotFoundError

        db = make_session()
        service = SchedulerService(db)
        request = SchedulerPlaceCreateRequest(
            place=SchedulerPlaceSelection(
                content_id="tour-333",
                title="아무 장소",
                category=PlaceCategory.TOURIST_ATTRACTION,
                latitude=37.5,
                longitude=127.0,
            ),
            day_no=1,
            visit_order=1,
        )
        with self.assertRaises(SchedulerNotFoundError):
            service.add_place(1, scheduler_id=9999, request=request)
        db.close()


if __name__ == "__main__":
    unittest.main()