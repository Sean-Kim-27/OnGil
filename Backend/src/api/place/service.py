from __future__ import annotations

import asyncio
import logging
import math
import re
from collections import Counter
from datetime import datetime, timezone
from difflib import SequenceMatcher
from typing import Any, Protocol
from urllib.parse import urlparse, urlunparse

from api.place.schemas import (
    KakaoPlaceLinkResponse,
    NearbyPlace,
    NearbyPlaceCounts,
    NearbyPlacesResponse,
    PlaceAnchor,
    PlaceCategory,
)
from infra.kakao_local import KakaoLocalError
from infra.tour_api import TourApiError

logger = logging.getLogger(__name__)


# 음식점/관광지(=향수를 자극하는 카테고리)에만 적용하는 거리/연식 가중치.
# 카페는 "오래됨 = 매력"이 성립하지 않고 대체할 품질 신호(리뷰/별점)도 없어서
# 거리 점수만 사용한다 (AGE_WEIGHTED_CATEGORIES에 속하지 않음).
DISTANCE_WEIGHT = 0.3
AGE_WEIGHT = 0.7
AGE_SCALE_YEARS = 20  # 연식 점수가 얼마나 빨리 1에 수렴하는지 조절하는 기준선
AGE_WEIGHTED_CATEGORIES = {PlaceCategory.RESTAURANT, PlaceCategory.TOURIST_ATTRACTION}


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


class KakaoPlaceLinkNotFoundError(RuntimeError):
    """Raised when Kakao has no trustworthy match for a TourAPI place."""


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


class KakaoPlaceSearchClientProtocol(Protocol):
    async def search_keyword(
        self,
        keyword: str,
        *,
        longitude: float | None = None,
        latitude: float | None = None,
        radius_m: int | None = None,
        sort: str = "accuracy",
    ) -> list[dict[str, Any]]: ...


class KakaoPlaceLinkService:
    """Resolve one selected TourAPI place to a Kakao place landing URL."""

    SEARCH_RADIUS_M = 300
    MIN_TITLE_SIMILARITY = 0.75

    def __init__(self, client: KakaoPlaceSearchClientProtocol) -> None:
        self.client = client

    async def resolve(
        self,
        *,
        title: str,
        latitude: float,
        longitude: float,
    ) -> KakaoPlaceLinkResponse:
        candidates = await self.client.search_keyword(
            title,
            longitude=longitude,
            latitude=latitude,
            radius_m=self.SEARCH_RADIUS_M,
            sort="distance",
        )
        match = self._select_match(title, candidates)
        if match is None:
            raise KakaoPlaceLinkNotFoundError(
                f"'{title}'에 일치하는 카카오 장소 상세 페이지를 찾지 못했습니다."
            )

        kakao_place_id = _optional_str(match.get("contentid"))
        place_url = _safe_kakao_place_url(match.get("place_url"))
        if kakao_place_id is None or place_url is None:
            raise KakaoPlaceLinkNotFoundError(
                f"'{title}'의 카카오 장소 상세 페이지를 확인할 수 없습니다."
            )
        return KakaoPlaceLinkResponse(
            kakao_place_id=kakao_place_id,
            place_url=place_url,
        )

    def _select_match(
        self,
        title: str,
        candidates: list[dict[str, Any]],
    ) -> dict[str, Any] | None:
        scored: list[tuple[float, float, dict[str, Any]]] = []
        for candidate in candidates:
            candidate_title = _optional_str(candidate.get("title"))
            distance_m = _as_float(candidate.get("distance_m"))
            if (
                candidate_title is None
                or distance_m is None
                or distance_m < 0
                or distance_m > self.SEARCH_RADIUS_M
                or _optional_str(candidate.get("contentid")) is None
                or _safe_kakao_place_url(candidate.get("place_url")) is None
            ):
                continue

            similarity = _title_similarity(title, candidate_title)
            if similarity >= self.MIN_TITLE_SIMILARITY:
                scored.append((similarity, -distance_m, candidate))

        if not scored:
            return None
        return max(scored, key=lambda item: (item[0], item[1]))[2]


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
            place = _to_nearby_place(item, category, related_by_title, radius_m)
            if (
                place is not None
                and place.content_id not in seen_content_ids
                and not _is_anchor_place(place, anchor_item)
            ):
                seen_content_ids.add(place.content_id)
                places.append(place)

        places.sort(key=lambda place: (-place.total_score, place.distance_m))
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
        content_type_id=_as_int(item.get("contenttypeid")),
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


def _is_anchor_place(place: NearbyPlace, anchor_item: dict[str, Any]) -> bool:
    """Return whether a nearby result is the searched anchor itself."""
    anchor_content_id = _optional_str(anchor_item.get("contentid"))
    if anchor_content_id is not None and place.content_id == anchor_content_id:
        return True

    anchor_title = _optional_str(anchor_item.get("title"))
    return (
        place.distance_m <= 25
        and anchor_title is not None
        and _normalize_title(place.title) == _normalize_title(anchor_title)
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


def _title_similarity(left: str, right: str) -> float:
    normalized_left = _normalize_title(left)
    normalized_right = _normalize_title(right)
    if not normalized_left or not normalized_right:
        return 0.0
    if normalized_left == normalized_right:
        return 1.0
    if normalized_left in normalized_right or normalized_right in normalized_left:
        return min(len(normalized_left), len(normalized_right)) / max(
            len(normalized_left), len(normalized_right)
        )
    return SequenceMatcher(None, normalized_left, normalized_right).ratio()


def _safe_kakao_place_url(value: Any) -> str | None:
    url = _optional_str(value)
    if url is None:
        return None
    parsed = urlparse(url)
    if (
        parsed.scheme not in {"http", "https"}
        or parsed.hostname != "place.map.kakao.com"
    ):
        return None
    return urlunparse(parsed._replace(scheme="https"))


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
