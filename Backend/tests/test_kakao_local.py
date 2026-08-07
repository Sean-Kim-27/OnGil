import os
import unittest

os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("GOOGLE_CLIENT_ID", "test.apps.googleusercontent.com")
os.environ.setdefault("KAKAO_APP_ID", "1234")
os.environ.setdefault("JWT_SECRET_KEY", "test-only-secret-key-with-32-characters")

import httpx

from infra.kakao_local import KakaoLocalClient, KakaoLocalError


class KakaoLocalClientTests(unittest.IsolatedAsyncioTestCase):
    async def test_searches_all_place_categories_and_normalizes_anchor(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            self.assertEqual(request.url.path, "/v2/local/search/keyword.json")
            self.assertEqual(request.headers["Authorization"], "KakaoAK rest-key")
            self.assertEqual(request.url.params["query"], "한국교통대학교")
            self.assertNotIn("category_group_code", request.url.params)
            return httpx.Response(
                200,
                json={
                    "documents": [
                        {
                            "id": "school-1",
                            "place_name": "한국교통대학교 충주캠퍼스",
                            "category_name": "교육,학문 > 학교 > 대학교",
                            "category_group_code": "SC4",
                            "category_group_name": "학교",
                            "address_name": "충북 충주시 대소원면 검단리 123",
                            "road_address_name": "충북 충주시 대학로 50",
                            "x": "127.871",
                            "y": "36.968",
                            "place_url": "https://place.map.kakao.com/1",
                        }
                    ]
                },
            )

        async with httpx.AsyncClient(
            transport=httpx.MockTransport(handler)
        ) as http_client:
            client = KakaoLocalClient(
                rest_api_key="rest-key",
                client=http_client,
            )
            results = await client.search_keyword("한국교통대학교")

        self.assertEqual(results[0]["title"], "한국교통대학교 충주캠퍼스")
        self.assertEqual(results[0]["category_group_code"], "SC4")
        self.assertEqual(results[0]["addr1"], "충북 충주시 대학로 50")
        self.assertEqual(results[0]["source"], "kakao")

    async def test_rejects_malformed_response(self) -> None:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(
                lambda request: httpx.Response(200, json={"documents": {}})
            )
        ) as http_client:
            client = KakaoLocalClient(
                rest_api_key="rest-key",
                client=http_client,
            )
            with self.assertRaises(KakaoLocalError):
                await client.search_keyword("래미안아파트")


if __name__ == "__main__":
    unittest.main()
