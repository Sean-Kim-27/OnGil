from __future__ import annotations

import asyncio
import math
import re
from datetime import datetime, timezone
from typing import Any, Protocol

from api.place.schemas import (
    NearbyPlace,
    NearbyPlaceCounts,
    NearbyPlacesResponse,
    PlaceAnchor,
    PlaceCategory,
)
from infra.tour_api import TourApiError

# 음식점/관광지(=향수를 자극하는 카테고리)에만 적용하는 거리/연식 가중치.
# 카페는 "오래됨 = 매력"이 성립하지 않고 대체할 품질 신호(리뷰/별점)도 없어서
# 거리 점수만 사용한다 (AGE_WEIGHTED_CATEGORIES에 속하지 않음).
DISTANCE_WEIGHT = 0.3
AGE_WEIGHT = 0.7
AGE_SCALE_YEARS = 20  # 연식 점수가 얼마나 빨리 1에 수렴하는지 조절하는 기준선
AGE_WEIGHTED_CATEGORIES = {PlaceCategory.RESTAURANT, PlaceCategory.TOURIST_ATTRACTION}


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
        content_type_id: int,
    ) -> tuple[list[dict[str, Any]], bool]: ...

    async def related(
        self,
        *,
        keyword: str,
        area_code: str,
        signgu_code: str,
        base_ym: str | None = None,
    ) -> tuple[list[dict[str, Any]], bool]: ...


class NearbyPlaceService:
    def __init__(self, client: TourApiClientProtocol) -> None:
        self.client = client

    async def search(self, *, query: str, radius_m: int) -> NearbyPlacesResponse:
        candidates = await self.client.search_keyword(query)
        anchor_item = _select_anchor(query, candidates)
        if anchor_item is None:
            raise PlaceNotFoundError(f"'{query}'에 해당하는 장소를 찾지 못했습니다.")

        latitude = _as_float(anchor_item.get("mapy"))
        longitude = _as_float(anchor_item.get("mapx"))
        if latitude is None or longitude is None:
            raise PlaceNotFoundError(f"'{query}'의 좌표를 확인할 수 없습니다.")

        related_task = self._related_safely(anchor_item)
        food_result, tourist_result, related_result = await asyncio.gather(
            self.client.nearby(
                longitude=longitude,
                latitude=latitude,
                radius_m=radius_m,
                content_type_id=39,
            ),
            self.client.nearby(
                longitude=longitude,
                latitude=latitude,
                radius_m=radius_m,
                content_type_id=12,
            ),
            related_task,
        )

        food_items, food_truncated = food_result
        tourist_items, tourist_truncated = tourist_result
        related_items, _, related_applied = related_result
        related_by_title = _index_related_places(related_items)

        places: list[NearbyPlace] = []
        seen_content_ids: set[str] = set()
        for item in food_items:
            category = (
                PlaceCategory.CAFE
                if str(item.get("lclsSystm2", "")).upper() == "FD05"
                else PlaceCategory.RESTAURANT
            )
            place = _to_nearby_place(item, category, related_by_title, radius_m)
            if place is not None and place.content_id not in seen_content_ids:
                seen_content_ids.add(place.content_id)
                places.append(place)

        for item in tourist_items:
            place = _to_nearby_place(
                item,
                PlaceCategory.TOURIST_ATTRACTION,
                related_by_title,
                radius_m,
            )
            if place is not None and place.content_id not in seen_content_ids:
                seen_content_ids.add(place.content_id)
                places.append(place)

        places.sort(key=lambda place: (-place.total_score, place.distance_m))
        restaurants = sum(
            place.category == PlaceCategory.RESTAURANT for place in places
        )
        cafes = sum(place.category == PlaceCategory.CAFE for place in places)
        tourist_attractions = sum(
            place.category == PlaceCategory.TOURIST_ATTRACTION for place in places
        )

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
                restaurant=restaurants,
                cafe=cafes,
                tourist_attraction=tourist_attractions,
                total=len(places),
            ),
            places=places,
            truncated=food_truncated or tourist_truncated,
            related_enrichment_applied=related_applied,
        )

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

    normalized_query = _normalize_title(query)
    for candidate in usable:
        if _normalize_title(str(candidate.get("title", ""))) == normalized_query:
            return candidate
    for candidate in usable:
        title = _normalize_title(str(candidate.get("title", "")))
        if normalized_query in title or title in normalized_query:
            return candidate
    return usable[0]


def _to_nearby_place(
    item: dict[str, Any],
    category: PlaceCategory,
    related_by_title: dict[str, dict[str, Any]],
    radius_m: int,
) -> NearbyPlace | None:
    content_id = _optional_str(item.get("contentid"))
    title = _optional_str(item.get("title"))
    distance = _as_float(item.get("dist"))
    if not content_id or not title or distance is None or distance < 0:
        return None

    distance_m = round(distance)
    distance_score = max(0.0, 1.0 - (distance_m / radius_m))

    registered_year = _registered_year(item.get("createdtime"))
    if category in AGE_WEIGHTED_CATEGORIES:
        if registered_year is not None:
            current_year = datetime.now(timezone.utc).year
            age_years = max(0, current_year - registered_year)
            # 오래될수록 계속(아주 조금씩이라도) 점수가 올라가되 1.0을 넘지 않도록
            # 지수적으로 수렴시킨다 (특정 연차 이후 전부 동점 처리되는 걸 방지).
            age_score = 1 - math.exp(-age_years / AGE_SCALE_YEARS)
        else:
            age_score = 0.0
        total_score = round(
            DISTANCE_WEIGHT * distance_score + AGE_WEIGHT * age_score, 4
        )
    else:
        # 카페 등 "오래됨 = 매력"이 성립하지 않는 카테고리는 거리 점수만 사용.
        age_score = 0.0
        total_score = round(distance_score, 4)

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
        distance_m=distance_m,
        image_url=_optional_str(item.get("firstimage")),
        thumbnail_url=_optional_str(item.get("firstimage2")),
        telephone=_optional_str(item.get("tel")),
        classification_code=_optional_str(item.get("lclsSystm3")),
        related_rank=related_rank if related_rank and related_rank > 0 else None,
        related_category=_first_str(
            relation,
            "rlteCtgrySclsNm",
            "rlteCtgryMclsNm",
            "rlteCtgryLclsNm",
        ),
        registered_year=registered_year,
        distance_score=round(distance_score, 4),
        age_score=round(age_score, 4),
        total_score=total_score,
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


def _registered_year(value: Any) -> int | None:
    text = _optional_str(value)
    if not text or len(text) < 4 or not text[:4].isdigit():
        return None
    year = int(text[:4])
    if year < 1900 or year > datetime.now(timezone.utc).year:
        return None
    return year


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