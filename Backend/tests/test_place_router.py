import os
import unittest
from types import SimpleNamespace

os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("GOOGLE_CLIENT_ID", "test.apps.googleusercontent.com")
os.environ.setdefault("KAKAO_APP_ID", "1234")
os.environ.setdefault("JWT_SECRET_KEY", "test-only-secret-key-with-32-characters")
os.environ["ENVIRONMENT"] = "test"
os.environ["REDIS_URL"] = ""

from api.place.router import get_nearby_place_service
from api.place.schemas import (
    NearbyPlace,
    NearbyPlaceCounts,
    NearbyPlacesResponse,
    PlaceAnchor,
    PlaceCategory,
)
from core.dependencies import get_current_user
from fastapi.testclient import TestClient
from main import app


class FakeNearbyPlaceService:
    async def search(self, *, query: str, radius_m: int) -> NearbyPlacesResponse:
        return NearbyPlacesResponse(
            query=query,
            radius_m=radius_m,
            anchor=PlaceAnchor(
                content_id="anchor",
                title="경복궁",
                latitude=37.5796,
                longitude=126.9769,
            ),
            counts=NearbyPlaceCounts(
                restaurant=0,
                cafe=1,
                tourist_attraction=0,
                total=1,
            ),
            places=[
                NearbyPlace(
                    content_id="cafe-1",
                    title="고궁카페",
                    category=PlaceCategory.CAFE,
                    distance_m=80,
                )
            ],
            truncated=False,
            related_enrichment_applied=False,
        )


class NearbyPlaceRouterTests(unittest.TestCase):
    def setUp(self) -> None:
        app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(id=1)
        app.dependency_overrides[get_nearby_place_service] = (
            lambda: FakeNearbyPlaceService()
        )
        self.client = TestClient(app)

    def tearDown(self) -> None:
        self.client.close()
        app.dependency_overrides.pop(get_current_user, None)
        app.dependency_overrides.pop(get_nearby_place_service, None)

    def test_returns_nearby_places(self) -> None:
        response = self.client.get(
            "/api/v1/places/nearby",
            params={"query": "경복궁", "radius_m": 5000},
            headers={"Authorization": "Bearer ongil-access-token"},
        )

        self.assertEqual(response.status_code, 200)
        self.assertEqual(response.json()["counts"]["total"], 1)
        self.assertEqual(response.json()["places"][0]["category"], "cafe")

    def test_requires_ongil_access_token(self) -> None:
        app.dependency_overrides.pop(get_current_user, None)
        try:
            response = self.client.get(
                "/api/v1/places/nearby",
                params={"query": "경복궁", "radius_m": 3000},
            )
        finally:
            app.dependency_overrides[get_current_user] = lambda: SimpleNamespace(id=1)

        self.assertEqual(response.status_code, 401)
        self.assertEqual(response.headers["WWW-Authenticate"], "Bearer")

    def test_rejects_radius_outside_three_to_five_kilometers(self) -> None:
        for radius_m in (2999, 5001):
            with self.subTest(radius_m=radius_m):
                response = self.client.get(
                    "/api/v1/places/nearby",
                    params={"query": "경복궁", "radius_m": radius_m},
                )
                self.assertEqual(response.status_code, 422)

    def test_rejects_whitespace_only_query(self) -> None:
        response = self.client.get(
            "/api/v1/places/nearby",
            params={"query": "   "},
        )
        self.assertEqual(response.status_code, 422)


if __name__ == "__main__":
    unittest.main()
