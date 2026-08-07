from __future__ import annotations

import asyncio
import logging
import re
from collections import Counter
from typing import Any, Protocol

from api.place.schemas import (
    NearbyPlace,
    NearbyPlaceCounts,
    NearbyPlacesResponse,
    PlaceAnchor,
    PlaceCategory,
)
from infra.kakao_local import KakaoLocalError
from infra.tour_api import TourApiError

logger = logging.getLogger(__name__)


CONTENT_TYPE_CATEGORIES: dict[int, PlaceCategory] = {
    12: PlaceCategory.TOURIST_ATTRACTION,
    14: PlaceCategory.CULTURAL_FACILITY,
    15: PlaceCategory.FESTIVAL,
    25: PlaceCategory.TRAVEL_COURSE,
    28: PlaceCategory.LEISURE_SPORTS,
    32: PlaceCategory.ACCOMMODATION,
    38: PlaceCategory.SHOPPING,
    39: PlaceCategory.RESTAURANT,
}

ANCHOR_SEARCH_FIELDS = (
    "title",
    "addr1",
    "addr2",
    "category_name",
    "category_group_name",
    "category_group_code",
    "lclsSystm1",
    "lclsSystm2",
    "lclsSystm3",
    "cat1",
    "cat2",
    "cat3",
    "contenttypeid",
)


class PlaceNotFoundError(RuntimeError):
    """Raised when a keyword cannot be resolved to a place with coordinates."""


class TourApiClientProtocol(Protocol):
    async def search_keyword(self, keyword: str) -> list[dict[str, Any]]: ...

    async def nearby(
        self,
        *,
        longitude: float,
        latitude: float,
        radius_m: int,
        content_type_id: int | None = None,
    ) -> tuple[list[dict[str, Any]], bool]: ...

    async def related(
        self,
        *,
        keyword: str,
        area_code: str,
        signgu_code: str,
        base_ym: str | None = None,
    ) -> tuple[list[dict[str, Any]], bool]: ...


class AnchorSearchClientProtocol(Protocol):
    async def search_keyword(self, keyword: str) -> list[dict[str, Any]]: ...


class NearbyPlaceService:
    def __init__(
        self,
        client: TourApiClientProtocol,
        anchor_client: AnchorSearchClientProtocol | None = None,
    ) -> None:
        self.client = client
        self.anchor_client = anchor_client

    async def search(self, *, query: str, radius_m: int) -> NearbyPlacesResponse:
        candidates = await self._search_anchor_candidates(query)
        anchor_item = _select_anchor(query, candidates)
        if anchor_item is None:
            raise PlaceNotFoundError(f"'{query}'에 해당하는 장소를 찾지 못했습니다.")

        latitude = _as_float(anchor_item.get("mapy"))
        longitude = _as_float(anchor_item.get("mapx"))
        if latitude is None or longitude is None:
            raise PlaceNotFoundError(f"'{query}'의 좌표를 확인할 수 없습니다.")

        related_task = self._related_safely(anchor_item)
        nearby_result, related_result = await asyncio.gather(
            self.client.nearby(
                longitude=longitude,
                latitude=latitude,
                radius_m=radius_m,
            ),
            related_task,
        )

        nearby_items, nearby_truncated = nearby_result
        related_items, _, related_applied = related_result
        related_by_title = _index_related_places(related_items)

        places: list[NearbyPlace] = []
        seen_content_ids: set[str] = set()
        for item in nearby_items:
            category = _category_for_item(item)
            place = _to_nearby_place(item, category, related_by_title)
            if place is not None and place.content_id not in seen_content_ids:
                seen_content_ids.add(place.content_id)
                places.append(place)

        places.sort(key=lambda place: (place.distance_m, place.title))
        counts = Counter(place.category for place in places)

        return NearbyPlacesResponse(
            query=query,
            radius_m=radius_m,
            anchor=PlaceAnchor(
                content_id=_optional_str(anchor_item.get("contentid")),
                title=_optional_str(anchor_item.get("title")) or query,
                address=_optional_str(anchor_item.get("addr1")),
                address_detail=_optional_str(anchor_item.get("addr2")),
                latitude=latitude,
                longitude=longitude,
            ),
            counts=NearbyPlaceCounts(
                restaurant=counts[PlaceCategory.RESTAURANT],
                cafe=counts[PlaceCategory.CAFE],
                tourist_attraction=counts[PlaceCategory.TOURIST_ATTRACTION],
                cultural_facility=counts[PlaceCategory.CULTURAL_FACILITY],
                festival=counts[PlaceCategory.FESTIVAL],
                travel_course=counts[PlaceCategory.TRAVEL_COURSE],
                leisure_sports=counts[PlaceCategory.LEISURE_SPORTS],
                accommodation=counts[PlaceCategory.ACCOMMODATION],
                shopping=counts[PlaceCategory.SHOPPING],
                other=counts[PlaceCategory.OTHER],
                total=len(places),
            ),
            places=places,
            truncated=nearby_truncated,
            related_enrichment_applied=related_applied,
        )

    async def _search_anchor_candidates(
        self,
        query: str,
    ) -> list[dict[str, Any]]:
        if self.anchor_client is not None:
            try:
                candidates = await self.anchor_client.search_keyword(query)
            except KakaoLocalError:
                logger.warning(
                    "Kakao anchor search failed; falling back to TourAPI",
                    exc_info=True,
                )
                candidates = []
            if candidates:
                return candidates
        return await self.client.search_keyword(query)

    async def _related_safely(
        self,
        anchor_item: dict[str, Any],
    ) -> tuple[list[dict[str, Any]], bool, bool]:
        area_code = _first_str(
            anchor_item,
            "areacode",
            "areaCode",
            "lDongRegnCd",
        )
        signgu_code = _first_str(
            anchor_item,
            "sigungucode",
            "signguCode",
            "lDongSignguCd",
        )
        title = _optional_str(anchor_item.get("title"))
        if not area_code or not signgu_code or not title:
            return [], False, False

        try:
            items, truncated = await self.client.related(
                keyword=title,
                area_code=area_code,
                signgu_code=signgu_code,
            )
        except TourApiError:
            # Nearby results are still useful if optional relation enrichment fails.
            return [], False, False
        return items, truncated, True


def _select_anchor(
    query: str,
    candidates: list[dict[str, Any]],
) -> dict[str, Any] | None:
    usable = [
        candidate
        for candidate in candidates
        if _as_float(candidate.get("mapx")) is not None
        and _as_float(candidate.get("mapy")) is not None
    ]
    if not usable:
        return None

    return max(
        enumerate(usable),
        key=lambda indexed: (_anchor_score(query, indexed[1]), -indexed[0]),
    )[1]


def _anchor_score(query: str, candidate: dict[str, Any]) -> int:
    normalized_query = _normalize_title(query)
    title = _normalize_title(str(candidate.get("title", "")))
    if not normalized_query:
        return 0

    score = 0
    if title == normalized_query:
        score += 10_000
    elif normalized_query in title:
        score += 4_000
    elif title and title in normalized_query:
        score += 2_000

    searchable_values = [
        str(candidate.get(field, ""))
        for field in ANCHOR_SEARCH_FIELDS
        if candidate.get(field)
    ]
    normalized_values = [_normalize_title(value) for value in searchable_values]
    combined = _normalize_title(" ".join(searchable_values))
    if any(value == normalized_query for value in normalized_values):
        score += 1_500
    elif normalized_query in combined:
        score += 750

    tokens = _search_tokens(query)
    matched_tokens = sum(token in combined for token in tokens)
    score += matched_tokens * 150
    if tokens and matched_tokens == len(tokens):
        score += 500
    return score


def _search_tokens(value: str) -> list[str]:
    return [
        _normalize_title(token)
        for token in re.findall(r"[0-9a-zA-Z가-힣]+", value.lower())
        if _normalize_title(token)
    ]


def _category_for_item(item: dict[str, Any]) -> PlaceCategory:
    content_type_id = _as_int(item.get("contenttypeid"))
    middle_classification = str(item.get("lclsSystm2", "")).upper()
    if content_type_id == 39 and middle_classification == "FD05":
        return PlaceCategory.CAFE
    if content_type_id == 28 and middle_classification == "AC05":
        return PlaceCategory.ACCOMMODATION
    if content_type_id is None:
        return PlaceCategory.OTHER
    return CONTENT_TYPE_CATEGORIES.get(content_type_id, PlaceCategory.OTHER)


def _to_nearby_place(
    item: dict[str, Any],
    category: PlaceCategory,
    related_by_title: dict[str, dict[str, Any]],
) -> NearbyPlace | None:
    content_id = _optional_str(item.get("contentid"))
    title = _optional_str(item.get("title"))
    distance = _as_float(item.get("dist"))
    if not content_id or not title or distance is None or distance < 0:
        return None

    relation = related_by_title.get(_normalize_title(title), {})
    related_rank = _as_int(relation.get("rlteRank"))
    return NearbyPlace(
        content_id=content_id,
        title=title,
        category=category,
        address=_optional_str(item.get("addr1")),
        address_detail=_optional_str(item.get("addr2")),
        latitude=_as_float(item.get("mapy")),
        longitude=_as_float(item.get("mapx")),
        distance_m=round(distance),
        image_url=_optional_str(item.get("firstimage")),
        thumbnail_url=_optional_str(item.get("firstimage2")),
        telephone=_optional_str(item.get("tel")),
        content_type_id=_as_int(item.get("contenttypeid")),
        classification_code=_optional_str(item.get("lclsSystm3")),
        related_rank=related_rank if related_rank and related_rank > 0 else None,
        related_category=_first_str(
            relation,
            "rlteCtgrySclsNm",
            "rlteCtgryMclsNm",
            "rlteCtgryLclsNm",
        ),
    )


def _index_related_places(
    items: list[dict[str, Any]],
) -> dict[str, dict[str, Any]]:
    result: dict[str, dict[str, Any]] = {}
    for item in items:
        title = _first_str(item, "rlteTatsNm", "tAtsNm")
        if not title:
            continue
        key = _normalize_title(title)
        previous_rank = _as_int(result.get(key, {}).get("rlteRank"))
        current_rank = _as_int(item.get("rlteRank"))
        if key not in result or (
            current_rank is not None
            and (previous_rank is None or current_rank < previous_rank)
        ):
            result[key] = item
    return result


def _normalize_title(value: str) -> str:
    return re.sub(r"[^0-9a-z가-힣]", "", value.lower())


def _first_str(item: dict[str, Any], *keys: str) -> str | None:
    for key in keys:
        value = _optional_str(item.get(key))
        if value:
            return value
    return None


def _optional_str(value: Any) -> str | None:
    if value is None:
        return None
    result = str(value).strip()
    return result or None


def _as_float(value: Any) -> float | None:
    try:
        return float(value)
    except (TypeError, ValueError):
        return None


def _as_int(value: Any) -> int | None:
    try:
        return int(value)
    except (TypeError, ValueError):
        return None
