"""External-API-independent route ordering for scheduler places.

The optimizer intentionally knows nothing about FastAPI, persistence, or Kakao.
Callers provide points and an edge-cost provider; this keeps the core reusable
when the final API flow changes from geodesic distance to a road-time matrix.
"""

from __future__ import annotations

import math
from collections.abc import Sequence
from dataclasses import dataclass
from typing import Protocol

EARTH_RADIUS_M = 6_371_008.8
_COST_EPSILON = 1e-9


@dataclass(frozen=True, slots=True)
class RoutePoint:
    """One visitable coordinate identified by a stable application key."""

    key: str
    latitude: float
    longitude: float

    def __post_init__(self) -> None:
        if not self.key.strip():
            raise ValueError("경로 지점 key는 비어 있을 수 없습니다.")
        if not math.isfinite(self.latitude) or not -90 <= self.latitude <= 90:
            raise ValueError("latitude는 -90 이상 90 이하의 유한한 값이어야 합니다.")
        if not math.isfinite(self.longitude) or not -180 <= self.longitude <= 180:
            raise ValueError("longitude는 -180 이상 180 이하의 유한한 값이어야 합니다.")


class RouteCostProvider(Protocol):
    """Supplies a non-negative directed edge cost between two route points."""

    unit: str

    def cost(self, start: RoutePoint, end: RoutePoint) -> float:
        """Return the travel cost from ``start`` to ``end``."""


@dataclass(frozen=True, slots=True)
class GeodesicCostProvider:
    """Great-circle distance provider used by the low-call Kakao strategy."""

    unit: str = "meter"

    def cost(self, start: RoutePoint, end: RoutePoint) -> float:
        return haversine_distance_m(start, end)


@dataclass(frozen=True, slots=True)
class RouteOptimizationResult:
    """Immutable result of nearest-neighbor seeding followed by 2-opt."""

    origin: RoutePoint
    ordered_stops: tuple[RoutePoint, ...]
    destination: RoutePoint | None
    seed_cost: float
    optimized_cost: float
    cost_unit: str
    two_opt_passes: int

    @property
    def route(self) -> tuple[RoutePoint, ...]:
        if self.destination is None:
            return (self.origin, *self.ordered_stops)
        return (self.origin, *self.ordered_stops, self.destination)

    @property
    def improvement(self) -> float:
        return self.seed_cost - self.optimized_cost


class RouteOptimizer:
    """Deterministic open-route optimizer for a small set of selected places.

    Nearest-neighbor creates a cheap, deterministic seed. Best-improvement
    2-opt then removes avoidable detours. Candidate routes are fully rescored,
    rather than using the symmetric 2-opt delta shortcut, so a future directed
    Kakao travel-time matrix can be plugged in without changing this algorithm.
    """

    def __init__(
        self,
        cost_provider: RouteCostProvider,
        *,
        max_two_opt_passes: int = 100,
    ) -> None:
        if max_two_opt_passes < 0:
            raise ValueError("max_two_opt_passes는 0 이상이어야 합니다.")
        if not cost_provider.unit.strip():
            raise ValueError("cost provider의 unit은 비어 있을 수 없습니다.")
        self.cost_provider = cost_provider
        self.max_two_opt_passes = max_two_opt_passes

    def optimize(
        self,
        origin: RoutePoint,
        stops: Sequence[RoutePoint],
        *,
        destination: RoutePoint | None = None,
    ) -> RouteOptimizationResult:
        """Return every stop exactly once in a deterministic optimized order.

        ``origin`` is always fixed. ``destination`` is optional and, when
        supplied, is also fixed. A destination equal to the origin is allowed
        for callers that need a round trip.
        """

        stop_tuple = tuple(stops)
        self._validate_route_points(origin, stop_tuple, destination)

        seeded_stops = self._nearest_neighbor(origin, stop_tuple)
        seed_cost = self._route_cost(origin, seeded_stops, destination)
        optimized_stops, optimized_cost, passes = self._two_opt(
            origin,
            seeded_stops,
            destination,
            seed_cost,
        )

        return RouteOptimizationResult(
            origin=origin,
            ordered_stops=optimized_stops,
            destination=destination,
            seed_cost=seed_cost,
            optimized_cost=optimized_cost,
            cost_unit=self.cost_provider.unit,
            two_opt_passes=passes,
        )

    @staticmethod
    def _validate_route_points(
        origin: RoutePoint,
        stops: tuple[RoutePoint, ...],
        destination: RoutePoint | None,
    ) -> None:
        stop_keys = [stop.key for stop in stops]
        if len(stop_keys) != len(set(stop_keys)):
            raise ValueError("최적화할 장소 key는 중복될 수 없습니다.")
        if origin.key in stop_keys:
            raise ValueError("출발지 key는 방문 장소 key와 중복될 수 없습니다.")
        if destination is None:
            return
        if destination.key in stop_keys:
            raise ValueError("도착지 key는 방문 장소 key와 중복될 수 없습니다.")
        if destination.key == origin.key and destination != origin:
            raise ValueError(
                "왕복 경로의 도착지는 출발지와 동일한 좌표를 사용해야 합니다."
            )

    def _nearest_neighbor(
        self,
        origin: RoutePoint,
        stops: tuple[RoutePoint, ...],
    ) -> tuple[RoutePoint, ...]:
        remaining = list(stops)
        ordered: list[RoutePoint] = []
        current = origin

        while remaining:
            next_index = min(
                range(len(remaining)),
                key=lambda index: (
                    self._edge_cost(current, remaining[index]),
                    index,
                ),
            )
            current = remaining.pop(next_index)
            ordered.append(current)

        return tuple(ordered)

    def _two_opt(
        self,
        origin: RoutePoint,
        seeded_stops: tuple[RoutePoint, ...],
        destination: RoutePoint | None,
        seed_cost: float,
    ) -> tuple[tuple[RoutePoint, ...], float, int]:
        current = seeded_stops
        current_cost = seed_cost
        completed_passes = 0

        for _ in range(self.max_two_opt_passes):
            best_candidate = current
            best_cost = current_cost

            for start_index in range(len(current) - 1):
                for end_index in range(start_index + 1, len(current)):
                    candidate = (
                        current[:start_index]
                        + tuple(reversed(current[start_index : end_index + 1]))
                        + current[end_index + 1 :]
                    )
                    candidate_cost = self._route_cost(
                        origin,
                        candidate,
                        destination,
                    )
                    if candidate_cost < best_cost - _COST_EPSILON:
                        best_candidate = candidate
                        best_cost = candidate_cost

            if best_candidate == current:
                break

            current = best_candidate
            current_cost = best_cost
            completed_passes += 1

        return current, current_cost, completed_passes

    def _route_cost(
        self,
        origin: RoutePoint,
        stops: tuple[RoutePoint, ...],
        destination: RoutePoint | None,
    ) -> float:
        total = 0.0
        current = origin
        for stop in stops:
            total += self._edge_cost(current, stop)
            current = stop
        if destination is not None:
            total += self._edge_cost(current, destination)
        return total

    def _edge_cost(self, start: RoutePoint, end: RoutePoint) -> float:
        cost = float(self.cost_provider.cost(start, end))
        if not math.isfinite(cost) or cost < 0:
            raise ValueError(
                "cost provider는 0 이상의 유한한 경로 비용을 반환해야 합니다."
            )
        return cost


def optimize_geodesic_route(
    origin: RoutePoint,
    stops: Sequence[RoutePoint],
    *,
    destination: RoutePoint | None = None,
    max_two_opt_passes: int = 100,
) -> RouteOptimizationResult:
    """Convenience entry point for the one-Kakao-call MVP strategy."""

    return RouteOptimizer(
        GeodesicCostProvider(),
        max_two_opt_passes=max_two_opt_passes,
    ).optimize(origin, stops, destination=destination)


def haversine_distance_m(start: RoutePoint, end: RoutePoint) -> float:
    """Return the great-circle distance in meters between two WGS84 points."""

    start_latitude = math.radians(start.latitude)
    end_latitude = math.radians(end.latitude)
    latitude_delta = end_latitude - start_latitude
    longitude_delta = math.radians(end.longitude - start.longitude)

    haversine = (
        math.sin(latitude_delta / 2) ** 2
        + math.cos(start_latitude)
        * math.cos(end_latitude)
        * math.sin(longitude_delta / 2) ** 2
    )
    haversine = min(1.0, max(0.0, haversine))
    central_angle = 2 * math.atan2(
        math.sqrt(haversine),
        math.sqrt(1 - haversine),
    )
    return EARTH_RADIUS_M * central_angle
