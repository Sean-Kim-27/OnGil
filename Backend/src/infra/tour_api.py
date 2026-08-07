from __future__ import annotations

from dataclasses import dataclass
from datetime import datetime
from typing import Any
from urllib.parse import unquote
from zoneinfo import ZoneInfo

import httpx


class TourApiError(RuntimeError):
    """Base error for Korean Tourism Organization API calls."""


class TourApiConfigurationError(TourApiError):
    """Raised when required TourAPI configuration is missing."""


class TourApiUnavailableError(TourApiError):
    """Raised when TourAPI cannot be reached or returns a non-2xx response."""


class TourApiResponseError(TourApiError):
    """Raised when TourAPI returns an invalid or unsuccessful payload."""


@dataclass(frozen=True)
class TourApiPage:
    items: list[dict[str, Any]]
    page_no: int
    num_rows: int
    total_count: int


class TourApiClient:
    """Async client for KorService2 and TarRlteTarService1."""

    def __init__(
        self,
        *,
        service_base_url: str | None,
        relate_base_url: str | None,
        service_key: str | None,
        timeout_seconds: float = 8.0,
        page_size: int = 100,
        max_results: int = 2000,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        if not service_base_url or not service_key:
            raise TourApiConfigurationError(
                "국문관광정보서비스 환경변수가 설정되지 않았습니다."
            )

        self.service_base_url = service_base_url.rstrip("/")
        self.relate_base_url = relate_base_url.rstrip("/") if relate_base_url else None
        # The portal often supplies a percent-encoded key. Decode once before
        # httpx encodes query parameters so '%' is not encoded a second time.
        self.service_key = unquote(service_key)
        self.timeout_seconds = timeout_seconds
        self.page_size = page_size
        self.max_results = max_results
        self.client = client

    async def search_keyword(self, keyword: str) -> list[dict[str, Any]]:
        page = await self._request_page(
            self.service_base_url,
            "searchKeyword2",
            {
                "keyword": keyword,
                "arrange": "O",
                "numOfRows": 50,
                "pageNo": 1,
            },
        )
        return page.items

    async def nearby(
        self,
        *,
        longitude: float,
        latitude: float,
        radius_m: int,
        content_type_id: int,
    ) -> tuple[list[dict[str, Any]], bool]:
        params: dict[str, Any] = {
            "mapX": longitude,
            "mapY": latitude,
            "radius": radius_m,
            "contentTypeId": content_type_id,
            # S sorts by distance and does not exclude places without images.
            "arrange": "S",
        }
        return await self._fetch_all(
            self.service_base_url,
            "locationBasedList2",
            params,
        )

    async def related(
        self,
        *,
        keyword: str,
        area_code: str,
        signgu_code: str,
        base_ym: str | None = None,
    ) -> tuple[list[dict[str, Any]], bool]:
        if not self.relate_base_url:
            raise TourApiConfigurationError(
                "연관관광지정보 환경변수가 설정되지 않았습니다."
            )

        return await self._fetch_all(
            self.relate_base_url,
            "searchKeyword1",
            {
                "baseYm": base_ym
                or datetime.now(ZoneInfo("Asia/Seoul")).strftime("%Y%m"),
                "areaCd": area_code,
                "signguCd": signgu_code,
                "keyword": keyword,
            },
        )

    async def _fetch_all(
        self,
        base_url: str,
        operation: str,
        params: dict[str, Any],
    ) -> tuple[list[dict[str, Any]], bool]:
        items: list[dict[str, Any]] = []
        page_no = 1
        total_count: int | None = None

        while len(items) < self.max_results:
            page = await self._request_page(
                base_url,
                operation,
                {
                    **params,
                    "numOfRows": min(self.page_size, self.max_results - len(items)),
                    "pageNo": page_no,
                },
            )
            items.extend(page.items)
            total_count = page.total_count

            if not page.items or len(items) >= total_count:
                break
            page_no += 1

        truncated = total_count is not None and len(items) < total_count
        return items[: self.max_results], truncated

    async def _request_page(
        self,
        base_url: str,
        operation: str,
        params: dict[str, Any],
    ) -> TourApiPage:
        request_params = {
            "MobileOS": "ETC",
            "MobileApp": "OnGil",
            "serviceKey": self.service_key,
            "_type": "json",
            **params,
        }
        url = f"{base_url}/{operation}"

        try:
            if self.client is not None:
                response = await self.client.get(url, params=request_params)
            else:
                async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
                    response = await client.get(url, params=request_params)
            response.raise_for_status()
        except (httpx.TimeoutException, httpx.NetworkError) as exc:
            raise TourApiUnavailableError(
                "공공데이터 API에 연결할 수 없습니다."
            ) from exc
        except httpx.HTTPStatusError as exc:
            raise TourApiUnavailableError(
                f"공공데이터 API가 HTTP {exc.response.status_code}를 반환했습니다."
            ) from exc

        try:
            payload = response.json()
        except ValueError as exc:
            raise TourApiResponseError(
                "공공데이터 API가 JSON이 아닌 응답을 반환했습니다."
            ) from exc

        return self._parse_page(payload)

    @staticmethod
    def _parse_page(payload: Any) -> TourApiPage:
        if not isinstance(payload, dict):
            raise TourApiResponseError("공공데이터 API 응답 형식이 올바르지 않습니다.")

        response = payload.get("response")
        if not isinstance(response, dict):
            raise TourApiResponseError("공공데이터 API 응답 본문이 없습니다.")

        header = response.get("header") or {}
        result_code = str(header.get("resultCode", ""))
        result_message = str(header.get("resultMsg", "알 수 없는 오류"))
        if result_code not in {"00", "0000"}:
            if result_code == "03":
                return TourApiPage(items=[], page_no=1, num_rows=0, total_count=0)
            raise TourApiResponseError(
                f"공공데이터 API 오류 ({result_code}: {result_message})"
            )

        body = response.get("body") or {}
        if not isinstance(body, dict):
            raise TourApiResponseError("공공데이터 API 응답 body 형식이 올바르지 않습니다.")

        raw_items = body.get("items") or []
        if isinstance(raw_items, dict):
            raw_items = raw_items.get("item") or []
        if isinstance(raw_items, dict):
            raw_items = [raw_items]
        if not isinstance(raw_items, list):
            raw_items = []

        return TourApiPage(
            items=[item for item in raw_items if isinstance(item, dict)],
            page_no=_as_int(body.get("pageNo"), default=1),
            num_rows=_as_int(body.get("numOfRows"), default=len(raw_items)),
            total_count=_as_int(body.get("totalCount"), default=len(raw_items)),
        )


def _as_int(value: Any, *, default: int = 0) -> int:
    try:
        return int(value)
    except (TypeError, ValueError):
        return default
