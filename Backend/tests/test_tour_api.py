import os
import unittest

os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("GOOGLE_CLIENT_ID", "test.apps.googleusercontent.com")
os.environ.setdefault("KAKAO_APP_ID", "1234")
os.environ.setdefault("JWT_SECRET_KEY", "test-only-secret-key-with-32-characters")

import httpx

from infra.tour_api import TourApiClient, TourApiResponseError


def make_payload(
    *,
    items: list[dict] | None = None,
    page_no: int = 1,
    num_rows: int = 10,
    total_count: int = 0,
    result_code: str = "0000",
) -> dict:
    return {
        "response": {
            "header": {"resultCode": result_code, "resultMsg": "OK"},
            "body": {
                "items": {"item": items or []},
                "pageNo": page_no,
                "numOfRows": num_rows,
                "totalCount": total_count,
            },
        }
    }


class TourApiClientTests(unittest.IsolatedAsyncioTestCase):
    async def test_decodes_portal_key_once_and_parses_keyword_response(self) -> None:
        def handler(request: httpx.Request) -> httpx.Response:
            self.assertEqual(request.url.path, "/KorService2/searchKeyword2")
            self.assertEqual(request.url.params["serviceKey"], "encoded+key=")
            self.assertEqual(request.url.params["keyword"], "경복궁")
            return httpx.Response(
                200,
                json=make_payload(
                    items=[{"contentid": "1", "title": "경복궁"}],
                    total_count=1,
                ),
            )

        async with httpx.AsyncClient(
            transport=httpx.MockTransport(handler)
        ) as http_client:
            client = TourApiClient(
                service_base_url="https://example.test/KorService2/",
                relate_base_url="https://example.test/TarRlteTarService1",
                service_key="encoded%2Bkey%3D",
                client=http_client,
            )
            items = await client.search_keyword("경복궁")

        self.assertEqual(items[0]["contentid"], "1")

    async def test_fetches_all_nearby_pages_and_reports_truncation(self) -> None:
        requested_pages: list[int] = []

        def handler(request: httpx.Request) -> httpx.Response:
            self.assertNotIn("contentTypeId", request.url.params)
            page_no = int(request.url.params["pageNo"])
            requested_pages.append(page_no)
            if page_no == 1:
                items = [{"contentid": "1"}, {"contentid": "2"}]
            else:
                items = [{"contentid": "3"}]
            return httpx.Response(
                200,
                json=make_payload(
                    items=items,
                    page_no=page_no,
                    num_rows=len(items),
                    total_count=4,
                ),
            )

        async with httpx.AsyncClient(
            transport=httpx.MockTransport(handler)
        ) as http_client:
            client = TourApiClient(
                service_base_url="https://example.test/KorService2",
                relate_base_url=None,
                service_key="key",
                page_size=2,
                max_results=3,
                client=http_client,
            )
            items, truncated = await client.nearby(
                longitude=126.9,
                latitude=37.5,
                radius_m=3000,
            )

        self.assertEqual(requested_pages, [1, 2])
        self.assertEqual([item["contentid"] for item in items], ["1", "2", "3"])
        self.assertTrue(truncated)

    async def test_raises_for_unsuccessful_api_header(self) -> None:
        async with httpx.AsyncClient(
            transport=httpx.MockTransport(
                lambda request: httpx.Response(
                    200,
                    json=make_payload(result_code="22"),
                )
            )
        ) as http_client:
            client = TourApiClient(
                service_base_url="https://example.test/KorService2",
                relate_base_url=None,
                service_key="key",
                client=http_client,
            )
            with self.assertRaises(TourApiResponseError):
                await client.search_keyword("경복궁")


if __name__ == "__main__":
    unittest.main()
