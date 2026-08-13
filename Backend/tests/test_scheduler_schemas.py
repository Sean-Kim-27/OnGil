import os
import unittest

os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("GOOGLE_CLIENT_ID", "test.apps.googleusercontent.com")
os.environ.setdefault("KAKAO_APP_ID", "1234")
os.environ.setdefault("JWT_SECRET_KEY", "test-only-secret-key-with-32-characters")

from fastapi import FastAPI
from fastapi.testclient import TestClient

from api.scheduler.schemas import SchedulerCreateRequest, SchedulerStaysReplaceRequest

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
            "memory_place": {
                "name": "옛날 학교",
                "address": "서울특별시 중구 세종대로 1",
                "latitude": 37.5665,
                "longitude": 126.978,
            },
            "places": [
                {
                    "content_id": "tour-1",
                    "title": "오래된 냉면집",
                    "category": "restaurant",
                    "latitude": 37.567,
                    "longitude": 126.979,
                    "image_url": None,
                    "kakao_place_id": "kakao-1",
                    "place_url": "http://place.map.kakao.com/kakao-1",
                }
            ],
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

    def test_rejects_non_kakao_place_url(self) -> None:
        invalid_place = {
            **self.payload["places"][0],
            "place_url": "https://example.com/not-kakao",
        }
        response = self.client.post(
            "/schedulers",
            json={
                **self.payload,
                "places": [invalid_place],
            },
        )

        self.assertEqual(response.status_code, 422)

    def test_requires_kakao_id_and_url_as_a_pair(self) -> None:
        place = self.payload["places"][0]
        missing_url = {**place, "place_url": None}
        missing_id = {**place, "kakao_place_id": None}

        missing_url_response = self.client.post(
            "/schedulers",
            json={
                **self.payload,
                "places": [missing_url],
            },
        )
        missing_id_response = self.client.post(
            "/schedulers",
            json={
                **self.payload,
                "places": [missing_id],
            },
        )

        self.assertEqual(missing_url_response.status_code, 422)
        self.assertEqual(missing_id_response.status_code, 422)

    def test_requires_exactly_one_memory_place_source(self) -> None:
        without_memory = {**self.payload, "memory_place": None}
        missing_response = self.client.post("/schedulers", json=without_memory)
        both_response = self.client.post(
            "/schedulers",
            json={**self.payload, "memory_place_id": 1},
        )

        self.assertEqual(missing_response.status_code, 422)
        self.assertEqual(both_response.status_code, 422)

    def test_rejects_duplicate_places(self) -> None:
        first = self.payload["places"][0]
        different_place = {
            **first,
            "content_id": "tour-2",
            "kakao_place_id": "kakao-2",
            "place_url": "https://place.map.kakao.com/kakao-2",
        }

        duplicate_place_response = self.client.post(
            "/schedulers",
            json={**self.payload, "places": [first, first]},
        )
        different_place_response = self.client.post(
            "/schedulers", json={**self.payload, "places": [first, different_place]}
        )

        self.assertEqual(duplicate_place_response.status_code, 422)
        self.assertEqual(different_place_response.status_code, 200)

    def test_rejects_multiple_accommodations(self) -> None:
        accommodation = {
            **self.payload["places"][0],
            "content_id": "hotel-1",
            "title": "첫 번째 숙소",
            "category": "accommodation",
            "kakao_place_id": None,
            "place_url": None,
        }
        another = {
            **accommodation,
            "content_id": "hotel-2",
            "title": "두 번째 숙소",
        }

        response = self.client.post(
            "/schedulers",
            json={
                **self.payload,
                "trip_type": "OVERNIGHT",
                "end_datetime": "2026-09-02T18:00:00+09:00",
                "places": [accommodation, another],
            },
        )

        self.assertEqual(response.status_code, 422)

    def test_rejects_accommodation_for_same_day_trip(self) -> None:
        accommodation = {
            **self.payload["places"][0],
            "category": "accommodation",
        }

        response = self.client.post(
            "/schedulers",
            json={**self.payload, "places": [accommodation]},
        )

        self.assertEqual(response.status_code, 422)

    def test_allows_two_accommodations_for_two_nights(self) -> None:
        first = {
            **self.payload["places"][0],
            "content_id": "hotel-night-1",
            "title": "첫날 숙소",
            "category": "accommodation",
            "kakao_place_id": None,
            "place_url": None,
        }
        second = {
            **first,
            "content_id": "hotel-night-2",
            "title": "둘째 날 숙소",
        }

        response = self.client.post(
            "/schedulers",
            json={
                **self.payload,
                "trip_type": "OVERNIGHT",
                "end_datetime": "2026-09-03T18:00:00+09:00",
                "places": [first, second],
            },
        )

        self.assertEqual(response.status_code, 200)

    def test_stay_replacement_rejects_duplicate_place_and_invalid_range(self) -> None:
        with self.assertRaisesRegex(ValueError, "체크아웃 날짜"):
            SchedulerStaysReplaceRequest.model_validate(
                {
                    "stays": [
                        {
                            "scheduler_place_id": 1,
                            "check_in_date": "2026-09-02",
                            "check_out_date": "2026-09-02",
                        }
                    ]
                }
            )

        with self.assertRaisesRegex(ValueError, "중복 지정"):
            SchedulerStaysReplaceRequest.model_validate(
                {
                    "stays": [
                        {
                            "scheduler_place_id": 1,
                            "check_in_date": "2026-09-01",
                            "check_out_date": "2026-09-02",
                        },
                        {
                            "scheduler_place_id": 1,
                            "check_in_date": "2026-09-02",
                            "check_out_date": "2026-09-03",
                        },
                    ]
                }
            )


if __name__ == "__main__":
    unittest.main()
