from __future__ import annotations

from typing import Any

import httpx


class KakaoLocalError(RuntimeError):
    """Raised when Kakao Local cannot provide usable place results."""


class KakaoLocalClient:
    """Keyword place search client backed by the Kakao Local REST API."""

    SEARCH_URL = "https://dapi.kakao.com/v2/local/search/keyword.json"

    def __init__(
        self,
        *,
        rest_api_key: str,
        timeout_seconds: float = 5.0,
        client: httpx.AsyncClient | None = None,
    ) -> None:
        self.rest_api_key = rest_api_key
        self.timeout_seconds = timeout_seconds
        self.client = client

    async def search_keyword(self, keyword: str) -> list[dict[str, Any]]:
        headers = {"Authorization": f"KakaoAK {self.rest_api_key}"}
        params = {"query": keyword, "size": 15, "sort": "accuracy"}

        try:
            if self.client is not None:
                response = await self.client.get(
                    self.SEARCH_URL,
                    headers=headers,
                    params=params,
                )
            else:
                async with httpx.AsyncClient(timeout=self.timeout_seconds) as client:
                    response = await client.get(
                        self.SEARCH_URL,
                        headers=headers,
                        params=params,
                    )
            response.raise_for_status()
        except (httpx.TimeoutException, httpx.NetworkError) as exc:
            raise KakaoLocalError("카카오 장소 검색 API에 연결할 수 없습니다.") from exc
        except httpx.HTTPStatusError as exc:
            raise KakaoLocalError(
                f"카카오 장소 검색 API가 HTTP {exc.response.status_code}를 반환했습니다."
            ) from exc

        try:
            payload = response.json()
        except ValueError as exc:
            raise KakaoLocalError(
                "카카오 장소 검색 API가 JSON이 아닌 응답을 반환했습니다."
            ) from exc

        documents = payload.get("documents") if isinstance(payload, dict) else None
        if not isinstance(documents, list):
            raise KakaoLocalError("카카오 장소 검색 API 응답 형식이 올바르지 않습니다.")

        return [
            self._to_anchor_candidate(document)
            for document in documents
            if isinstance(document, dict)
        ]

    @staticmethod
    def _to_anchor_candidate(document: dict[str, Any]) -> dict[str, Any]:
        return {
            "contentid": document.get("id"),
            "title": document.get("place_name"),
            "addr1": document.get("road_address_name")
            or document.get("address_name"),
            "addr2": document.get("address_name"),
            "mapx": document.get("x"),
            "mapy": document.get("y"),
            "category_name": document.get("category_name"),
            "category_group_code": document.get("category_group_code"),
            "category_group_name": document.get("category_group_name"),
            "place_url": document.get("place_url"),
            "source": "kakao",
        }
