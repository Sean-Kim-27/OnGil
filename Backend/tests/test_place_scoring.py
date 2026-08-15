import os
import unittest

os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("GOOGLE_CLIENT_ID", "test.apps.googleusercontent.com")
os.environ.setdefault("KAKAO_APP_ID", "1234")
os.environ.setdefault("JWT_SECRET_KEY", "test-only-secret-key-with-32-characters")

from api.place.schemas import PlaceCategory
from api.place.service import NearbyPlaceService


class FakeTourApiClient:
    """오래된 음식점 vs 신상 카페 vs 오래된 카페를 섞어서 반환하는 fake."""

    async def search_keyword(self, keyword: str) -> list[dict]:
        return [
            {
                "contentid": "anchor",
                "title": "경복궁",
                "mapx": "126.9769",
                "mapy": "37.5796",
                "areacode": "1",
                "sigungucode": "23",
            }
        ]

    async def nearby(
        self, *, longitude, latitude, radius_m, content_type_id=None
    ):
        if content_type_id in (None, 39):
            return (
                [
                    {
                        "contentid": "anchor",
                        "title": "경복궁",
                        "dist": "0",
                        "mapx": "126.9769",
                        "mapy": "37.5796",
                        "contenttypeid": "12",
                        "createdtime": "20000101120000",
                    },
                    {
                        "contentid": "old-restaurant",
                        "title": "오래된 냉면집",
                        "dist": "500",
                        "mapx": "126.977",
                        "mapy": "37.580",
                        "contenttypeid": "39",
                        "lclsSystm2": "FD01",  # 일반 음식점
                        "createdtime": "20030101120000",
                    },
                    {
                        "contentid": "new-cafe",
                        "title": "신상 카페",
                        "dist": "300",
                        "mapx": "126.978",
                        "mapy": "37.581",
                        "contenttypeid": "39",
                        "lclsSystm2": "FD05",  # 카페
                        "createdtime": "20250101120000",
                    },
                    {
                        "contentid": "old-cafe-far",
                        "title": "오래된 다방(더 멂)",
                        "dist": "2900",
                        "mapx": "126.99",
                        "mapy": "37.60",
                        "contenttypeid": "39",
                        "lclsSystm2": "FD05",  # 카페
                        "createdtime": "19900101120000",
                    },
                ],
                False,
            )
        return [], False

    async def related(self, *, keyword, area_code, signgu_code, base_ym=None):
        return [], False


class PlaceScoringTests(unittest.IsolatedAsyncioTestCase):
    async def test_excludes_search_anchor_from_recommendations(self):
        service = NearbyPlaceService(FakeTourApiClient())
        result = await service.search(query="경복궁", radius_m=3000)

        self.assertEqual(result.anchor.content_id, "anchor")
        self.assertNotIn("anchor", [place.content_id for place in result.places])

    async def test_cafe_ignores_age_and_ranks_by_distance_only(self):
        service = NearbyPlaceService(FakeTourApiClient())
        result = await service.search(query="경복궁", radius_m=3000)

        cafes = [p for p in result.places if p.category == PlaceCategory.CAFE]
        self.assertEqual(len(cafes), 2)

        new_cafe = next(p for p in cafes if p.content_id == "new-cafe")
        old_cafe_far = next(p for p in cafes if p.content_id == "old-cafe-far")

        # 카페는 연식 점수가 절대 반영되면 안 됨 (1990년 등록이어도 age_score=0)
        self.assertEqual(new_cafe.age_score, 0.0)
        self.assertEqual(old_cafe_far.age_score, 0.0)

        # 가까운 신상 카페가 먼 노포 다방보다 순위가 높아야 함 (거리순 정렬)
        self.assertLess(new_cafe.distance_m, old_cafe_far.distance_m)
        self.assertGreater(new_cafe.total_score, old_cafe_far.total_score)

        cafe_order = [p.content_id for p in result.places if p.category == PlaceCategory.CAFE]
        self.assertEqual(cafe_order, ["new-cafe", "old-cafe-far"])

    async def test_restaurant_still_uses_age_weighted_score(self):
        service = NearbyPlaceService(FakeTourApiClient())
        result = await service.search(query="경복궁", radius_m=3000)

        old_restaurant = next(
            p for p in result.places if p.content_id == "old-restaurant"
        )
        self.assertGreater(old_restaurant.age_score, 0.0)
        # 가중합 공식(거리 30% + 연식 70%)대로 계산됐는지 확인
        expected_total = round(
            0.3 * old_restaurant.distance_score + 0.7 * old_restaurant.age_score, 4
        )
        self.assertAlmostEqual(old_restaurant.total_score, expected_total, places=4)


if __name__ == "__main__":
    unittest.main()
