import os
import unittest

os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("GOOGLE_CLIENT_ID", "test.apps.googleusercontent.com")
os.environ.setdefault("KAKAO_APP_ID", "1234")
os.environ.setdefault("JWT_SECRET_KEY", "test-only-secret-key-with-32-characters")

from fastapi import FastAPI
from fastapi.testclient import TestClient

from api.scheduler.schemas import SchedulerCreateRequest

app = FastAPI()


@app.post("/schedulers")
def validate_scheduler(request: SchedulerCreateRequest) -> dict[str, int]:
    return {"id": 1}


class SchedulerDatetimeValidationTests(unittest.TestCase):
    def setUp(self) -> None:
        self.client = TestClient(app)
        self.payload = {
            "title": "추억 여행",
            "mobility_mode": "WALK",
            "search_radius": 3,
            "trip_type": "DAY_TRIP",
            "companion_type": "FAMILY",
            "companion_count": 3,
            "start_datetime": "2026-09-01T09:00:00+09:00",
            "end_datetime": "2026-09-01T18:00:00+09:00",
        }

    def tearDown(self) -> None:
        self.client.close()

    def test_accepts_timezone_aware_datetimes(self) -> None:
        response = self.client.post("/schedulers", json=self.payload)

        self.assertEqual(response.status_code, 200)

    def test_rejects_mixed_timezone_datetimes_with_422(self) -> None:
        response = self.client.post(
            "/schedulers",
            json={**self.payload, "end_datetime": "2026-09-01T18:00:00"},
        )

        self.assertEqual(response.status_code, 422)
        self.assertEqual(response.json()["detail"][0]["loc"], ["body", "end_datetime"])

    def test_rejects_end_datetime_not_after_start(self) -> None:
        response = self.client.post(
            "/schedulers",
            json={
                **self.payload,
                "end_datetime": "2026-09-01T08:59:59+09:00",
            },
        )

        self.assertEqual(response.status_code, 422)

    def test_rejects_radius_other_than_three_or_five_kilometers(self) -> None:
        for radius in (1, 2, 4, 4.5):
            with self.subTest(radius=radius):
                response = self.client.post(
                    "/schedulers",
                    json={**self.payload, "search_radius": radius},
                )
                self.assertEqual(response.status_code, 422)


if __name__ == "__main__":
    unittest.main()
