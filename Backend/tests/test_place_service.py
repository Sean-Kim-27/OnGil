import os
import unittest

os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("GOOGLE_CLIENT_ID", "test.apps.googleusercontent.com")
os.environ.setdefault("KAKAO_APP_ID", "1234")
os.environ.setdefault("JWT_SECRET_KEY", "test-only-secret-key-with-32-characters")

from api.place.schemas import PlaceCategory
from api.place.service import NearbyPlaceService, PlaceNotFoundError, _select_anchor
from infra.tour_api import TourApiResponseError


class FakeTourApiClient:
    def __init__(self, *, related_error: bool = False) -> None:
        self.related_error = related_error
        self.nearby_content_type_ids: list[int | None] = []

    async def search_keyword(self, keyword: str) -> list[dict]:
        return [
            {
                "contentid": "anchor",
                "title": "경복궁",
                "addr1": "서울 종로구",
                "mapx": "126.9769",
                "mapy": "37.5796",
                "areacode": "1",
                "sigungucode": "23",
            }
        ]

    async def nearby(
        self,
        *,
        longitude: float,
        latitude: float,
        radius_m: int,
        content_type_id: int | None = None,
    ) -> tuple[list[dict], bool]:
        self.nearby_content_type_ids.append(content_type_id)
        return (
            [
                {
                    "contentid": "food-1",
                    "title": "궁중식당",
                    "dist": "220.6",
                    "mapx": "126.977",
                    "mapy": "37.580",
                    "contenttypeid": "39",
                    "lclsSystm2": "FD01",
                    "lclsSystm3": "FD010100",
                },
                {
                    "contentid": "cafe-1",
                    "title": "고궁카페",
                    "dist": "80",
                    "mapx": "126.978",
                    "mapy": "37.581",
                    "contenttypeid": "39",
                    "lclsSystm2": "FD05",
                    "lclsSystm3": "FD050100",
                },
                {
                    "contentid": "tour-1",
                    "title": "국립민속박물관",
                    "dist": "150",
                    "mapx": "126.979",
                    "mapy": "37.582",
                    "contenttypeid": "12",
                    "lclsSystm3": "VE010100",
                },
                {
                    "contentid": "culture-1",
                    "title": "고궁박물관",
                    "dist": "300",
                    "contenttypeid": "14",
                },
                {
                    "contentid": "stay-1",
                    "title": "한옥스테이",
                    "dist": "400",
                    "contenttypeid": "32",
                },
                {
                    "contentid": "camp-1",
                    "title": "도심글램핑",
                    "dist": "500",
                    "contenttypeid": "28",
                    "lclsSystm2": "AC05",
                },
            ],
            True,
        )

    async def related(
        self,
        *,
        keyword: str,
        area_code: str,
        signgu_code: str,
        base_ym: str | None = None,
    ) -> tuple[list[dict], bool]:
        if self.related_error:
            raise TourApiResponseError("relation failed")
        return (
            [
                {
                    "rlteTatsNm": "국립민속박물관",
                    "rlteRank": "2",
                    "rlteCtgrySclsNm": "박물관",
                }
            ],
            False,
        )


class NearbyPlaceServiceTests(unittest.IsolatedAsyncioTestCase):
    async def test_classifies_sorts_and_enriches_nearby_places(self) -> None:
        client = FakeTourApiClient()
        result = await NearbyPlaceService(client).search(
            query="경복궁",
            radius_m=5000,
        )

        self.assertEqual(result.anchor.title, "경복궁")
        self.assertEqual(result.counts.restaurant, 1)
        self.assertEqual(result.counts.cafe, 1)
        self.assertEqual(result.counts.tourist_attraction, 1)
        self.assertEqual(result.counts.cultural_facility, 1)
        self.assertEqual(result.counts.accommodation, 2)
        self.assertEqual(result.counts.total, 6)
        self.assertEqual(result.places[0].category, PlaceCategory.CAFE)
        self.assertEqual(result.places[0].content_type_id, 39)
        self.assertEqual(client.nearby_content_type_ids, [None])
        self.assertEqual(result.places[1].related_rank, 2)
        self.assertEqual(result.places[1].related_category, "박물관")
        self.assertTrue(result.related_enrichment_applied)
        self.assertTrue(result.truncated)

    async def test_keeps_nearby_results_when_optional_relation_api_fails(self) -> None:
        result = await NearbyPlaceService(
            FakeTourApiClient(related_error=True)
        ).search(query="경복궁", radius_m=3000)

        self.assertEqual(result.counts.total, 6)
        self.assertFalse(result.related_enrichment_applied)

    async def test_raises_when_keyword_has_no_place_with_coordinates(self) -> None:
        client = FakeTourApiClient()

        async def no_results(keyword: str) -> list[dict]:
            return []

        client.search_keyword = no_results
        with self.assertRaises(PlaceNotFoundError):
            await NearbyPlaceService(client).search(query="없는장소", radius_m=3000)

    def test_selects_anchor_using_title_address_and_category_tags(self) -> None:
        candidates = [
            {
                "title": "서울대학교입구역",
                "addr1": "서울 동작구",
                "category_name": "교통 > 지하철역",
                "mapx": "126.952",
                "mapy": "37.481",
            },
            {
                "title": "관악캠퍼스 정문",
                "addr1": "서울 관악구",
                "category_name": "교육 > 학교 > 대학교",
                "mapx": "126.950",
                "mapy": "37.460",
            },
        ]

        selected = _select_anchor("서울 관악구 대학교", candidates)

        self.assertIsNotNone(selected)
        self.assertEqual(selected["title"], "관악캠퍼스 정문")


if __name__ == "__main__":
    unittest.main()
