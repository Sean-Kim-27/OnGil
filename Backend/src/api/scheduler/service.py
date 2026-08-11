from __future__ import annotations

import math
from datetime import datetime, timezone
from typing import Any, Protocol

from sqlalchemy import select
from sqlalchemy.orm import Session, selectinload

from api.place.models import MemoryPlace
from api.place.schemas import PlaceCategory
from api.scheduler.models import Scheduler, SchedulerPlace
from api.scheduler.schemas import (
    RecommendedPlace,
    SchedulerCreateRequest,
    SchedulerPlaceCreateRequest,
)

# 거리/연식 가중치. 합이 1.0이 되도록 맞춰두고, 추후 튜닝 시 이 값만 조정하면 됨.
DISTANCE_WEIGHT = 0.3
AGE_WEIGHT = 0.7
AGE_SCALE_YEARS = 20  # 연식 점수가 얼마나 빨리 1에 수렴하는지 조절하는 기준선
DEFAULT_RECOMMENDATION_LIMIT = 20

_CONTENT_TYPE_BY_CATEGORY: dict[PlaceCategory, int] = {
    PlaceCategory.RESTAURANT: 39,
    PlaceCategory.TOURIST_ATTRACTION: 12,
}


class SchedulerNotFoundError(RuntimeError):
    """Raised when a scheduler cannot be found for the current user."""


class MemoryPlaceNotFoundError(RuntimeError):
    """Raised when the scheduler's memory place anchor cannot be found."""


class TourApiClientProtocol(Protocol):
    async def nearby(
        self,
        *,
        longitude: float,
        latitude: float,
        radius_m: int,
        content_type_id: int,
    ) -> tuple[list[dict[str, Any]], bool]: ...


class SchedulerService:
    """Scheduler(일정) 생성/조회/장소 추가 등 CRUD를 담당."""

    def __init__(self, db: Session) -> None:
        self.db = db

    def create(self, user_id: int, request: SchedulerCreateRequest) -> Scheduler:
        if request.memory_place_id is not None:
            self._get_owned_memory_place(user_id, request.memory_place_id)

        scheduler = Scheduler(
            user_id=user_id,
            title=request.title,
            mobility_mode=request.mobility_mode,
            search_radius=request.search_radius,
            trip_type=request.trip_type,
            memory_place_id=request.memory_place_id,
            companion_type=request.companion_type,
            companion_count=request.companion_count,
            start_datetime=request.start_datetime,
            end_datetime=request.end_datetime,
        )
        self.db.add(scheduler)
        self.db.commit()
        self.db.refresh(scheduler)
        return scheduler

    def get_owned(self, user_id: int, scheduler_id: int) -> Scheduler:
        scheduler = self.db.scalar(
            select(Scheduler)
            .options(selectinload(Scheduler.places))
            .where(Scheduler.id == scheduler_id, Scheduler.user_id == user_id)
        )
        if scheduler is None:
            raise SchedulerNotFoundError(f"스케줄러(id={scheduler_id})를 찾을 수 없습니다.")
        return scheduler

    def list_owned(self, user_id: int) -> list[Scheduler]:
        return list(
            self.db.scalars(
                select(Scheduler)
                .options(selectinload(Scheduler.places))
                .where(Scheduler.user_id == user_id)
                .order_by(Scheduler.created_at.desc())
            )
        )

    def delete_owned(self, user_id: int, scheduler_id: int) -> None:
        scheduler = self.get_owned(user_id, scheduler_id)
        self.db.delete(scheduler)
        self.db.commit()

    def add_place(
        self,
        user_id: int,
        scheduler_id: int,
        request: SchedulerPlaceCreateRequest,
    ) -> SchedulerPlace:
        scheduler = self.get_owned(user_id, scheduler_id)
        scheduler_place = SchedulerPlace(
            scheduler_id=scheduler.id,
            place_id=request.place_id,
            day_no=request.day_no,
            time_slot=request.time_slot,
            visit_order=request.visit_order,
        )
        self.db.add(scheduler_place)
        self.db.commit()
        self.db.refresh(scheduler_place)
        return scheduler_place

    def remove_place(
        self, user_id: int, scheduler_id: int, scheduler_place_id: int
    ) -> None:
        scheduler = self.get_owned(user_id, scheduler_id)
        scheduler_place = next(
            (place for place in scheduler.places if place.id == scheduler_place_id),
            None,
        )
        if scheduler_place is None:
            raise SchedulerNotFoundError(
                f"스케줄러 장소(id={scheduler_place_id})를 찾을 수 없습니다."
            )
        self.db.delete(scheduler_place)
        self.db.commit()

    def _get_owned_memory_place(self, user_id: int, memory_place_id: int) -> MemoryPlace:
        memory_place = self.db.scalar(
            select(MemoryPlace).where(
                MemoryPlace.id == memory_place_id,
                MemoryPlace.user_id == user_id,
            )
        )
        if memory_place is None:
            raise MemoryPlaceNotFoundError(
                f"추억의 장소(id={memory_place_id})를 찾을 수 없습니다."
            )
        return memory_place


class RecommendationService:
    """장소 연식 + 거리 가중치 기반 추천 로직."""

    def __init__(self, db: Session, client: TourApiClientProtocol) -> None:
        self.db = db
        self.client = client

    async def recommend(
        self,
        user_id: int,
        scheduler_id: int,
        limit: int = DEFAULT_RECOMMENDATION_LIMIT,
    ) -> tuple[Scheduler, MemoryPlace, list[RecommendedPlace]]:
        scheduler = self.db.scalar(
            select(Scheduler).where(
                Scheduler.id == scheduler_id, Scheduler.user_id == user_id
            )
        )
        if scheduler is None:
            raise SchedulerNotFoundError(f"스케줄러(id={scheduler_id})를 찾을 수 없습니다.")
        if scheduler.memory_place_id is None:
            raise MemoryPlaceNotFoundError(
                "이 스케줄러는 추억의 장소가 연결되어 있지 않아 추천할 수 없습니다."
            )

        memory_place = self.db.get(MemoryPlace, scheduler.memory_place_id)
        if memory_place is None:
            raise MemoryPlaceNotFoundError(
                f"추억의 장소(id={scheduler.memory_place_id})를 찾을 수 없습니다."
            )

        radius_m = _to_radius_m(scheduler.search_radius)

        candidates: list[RecommendedPlace] = []
        for category, content_type_id in _CONTENT_TYPE_BY_CATEGORY.items():
            items, _ = await self.client.nearby(
                longitude=memory_place.lng,
                latitude=memory_place.lat,
                radius_m=radius_m,
                content_type_id=content_type_id,
            )
            for item in items:
                place = _score_item(item, category, radius_m)
                if place is not None:
                    candidates.append(place)

        candidates.sort(key=lambda place: place.total_score, reverse=True)
        return scheduler, memory_place, candidates[:limit]


def _to_radius_m(search_radius_km: float) -> int:
    radius_m = round(search_radius_km * 1000)
    return max(3000, min(radius_m, 5000))


def _score_item(
    item: dict[str, Any],
    category: PlaceCategory,
    radius_m: int,
) -> RecommendedPlace | None:
    content_id = _optional_str(item.get("contentid"))
    title = _optional_str(item.get("title"))
    distance = _as_float(item.get("dist"))
    if not content_id or not title or distance is None or distance < 0:
        return None

    distance_m = round(distance)
    distance_score = max(0.0, 1.0 - (distance_m / radius_m))

    registered_year = _registered_year(item.get("createdtime"))
    if registered_year is not None:
        current_year = datetime.now(timezone.utc).year
        age_years = max(0, current_year - registered_year)
        # 20년 넘었다고 무조건 동점 처리하지 않고, 오래될수록 계속(아주 조금씩이라도)
        # 점수가 올라가되 1.0을 넘지 않도록 지수적으로 수렴시킴.
        age_score = 1 - math.exp(-age_years / AGE_SCALE_YEARS)
    else:
        age_score = 0.0

    total_score = round(DISTANCE_WEIGHT * distance_score + AGE_WEIGHT * age_score, 4)

    return RecommendedPlace(
        content_id=content_id,
        title=title,
        category=category.value,
        address=_optional_str(item.get("addr1")),
        latitude=_as_float(item.get("mapy")),
        longitude=_as_float(item.get("mapx")),
        distance_m=distance_m,
        registered_year=registered_year,
        distance_score=round(distance_score, 4),
        age_score=round(age_score, 4),
        total_score=total_score,
        image_url=_optional_str(item.get("firstimage")),
    )


def _registered_year(value: Any) -> int | None:
    text = _optional_str(value)
    if not text or len(text) < 4 or not text[:4].isdigit():
        return None
    year = int(text[:4])
    if year < 1900 or year > datetime.now(timezone.utc).year:
        return None
    return year


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