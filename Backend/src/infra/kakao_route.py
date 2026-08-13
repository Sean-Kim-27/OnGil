"""One-call Kakao route verification for an already ordered itinerary."""

from __future__ import annotations

from collections.abc import Sequence
from dataclasses import dataclass
from typing import Any, Protocol

import httpx

from api.scheduler.models import MobilityMode
from api.scheduler.route_optimizer import RoutePoint


class KakaoRouteError(RuntimeError):
    """Raised when Kakao cannot return a usable route."""


@dataclass(frozen=True, slots=True)
class RouteLeg:
    """Travel metrics from one route point to the next."""

    duration_seconds: int
    distance_m: int

    def __post_init__(self) -> None:
        if self.duration_seconds < 0 or self.distance_m < 0:
            raise ValueError("경로 구간의 시간과 거리는 0 이상이어야 합니다.")


class RouteVerifier(Protocol):
    """Verifies one pre-ordered route without changing its order."""

    def verify(
        self,
        mobility_mode: MobilityMode,
        route: Sequence[RoutePoint],
    ) -> tuple[RouteLeg, ...]:
        """Return one leg for every adjacent route-point pair."""


class KakaoRouteClient:
    """Kakao car/walk client that makes exactly one request per verification."""

    CAR_URL = "https://apis-navi.kakaomobility.com/v1/waypoints/directions"
    WALK_URL = "https://dapi.kakao.com/v2/routing/walk"
    MAX_CAR_STOPS = 31
    MAX_WALK_STOPS = 6

    def __init__(
        self,
        *,
        rest_api_key: str,
        timeout_seconds: float = 8.0,
        client: httpx.Client | None = None,
    ) -> None:
        if not rest_api_key.strip():
            raise ValueError("카카오 REST API 키는 비어 있을 수 없습니다.")
        self.rest_api_key = rest_api_key
        self.timeout_seconds = timeout_seconds
        self.client = client

    def verify(
        self,
        mobility_mode: MobilityMode,
        route: Sequence[RoutePoint],
    ) -> tuple[RouteLeg, ...]:
        route_tuple = tuple(route)
        if len(route_tuple) < 2:
            raise ValueError("경로 검증에는 출발지와 방문 장소가 필요합니다.")

        stops_count = len(route_tuple) - 1
        limit = (
            self.MAX_WALK_STOPS
            if mobility_mode == MobilityMode.WALK
            else self.MAX_CAR_STOPS
        )
        if stops_count > limit:
            raise KakaoRouteError(
                f"{mobility_mode.value} 경로는 한 번에 장소 {limit}개까지 검증할 수 있습니다."
            )

        if mobility_mode == MobilityMode.WALK:
            payload = self._request_walk(route_tuple)
            raw_legs = self._walk_legs(payload)
        else:
            payload = self._request_car(route_tuple)
            raw_legs = self._car_legs(payload)

        expected_count = len(route_tuple) - 1
        if len(raw_legs) != expected_count:
            raise KakaoRouteError(
                "카카오 경로 API가 요청 지점 수와 다른 구간 수를 반환했습니다."
            )
        return raw_legs

    def _request_car(self, route: tuple[RoutePoint, ...]) -> Any:
        waypoints = [self._car_point(point) for point in route[1:-1]]
        body: dict[str, Any] = {
            "origin": self._car_point(route[0]),
            "destination": self._car_point(route[-1]),
            "priority": "TIME",
            "alternatives": False,
            "road_details": False,
            # Per-section time/distance is omitted when summary is true.
            "summary": False,
        }
        if waypoints:
            body["waypoints"] = waypoints
        return self._request("POST", self.CAR_URL, json=body)

    def _request_walk(self, route: tuple[RoutePoint, ...]) -> Any:
        params: dict[str, str] = {
            "start_x": str(route[0].longitude),
            "start_y": str(route[0].latitude),
            "end_x": str(route[-1].longitude),
            "end_y": str(route[-1].latitude),
            "input_coord": "WGS84",
            "output_coord": "WGS84",
            "route_mode": "SHORTEST",
        }
        waypoints = route[1:-1]
        if waypoints:
            params["via_x"] = ",".join(str(point.longitude) for point in waypoints)
            params["via_y"] = ",".join(str(point.latitude) for point in waypoints)
        return self._request("GET", self.WALK_URL, params=params)

    def _request(self, method: str, url: str, **kwargs: Any) -> Any:
        headers = {"Authorization": f"KakaoAK {self.rest_api_key}"}
        try:
            if self.client is not None:
                response = self.client.request(
                    method,
                    url,
                    headers=headers,
                    **kwargs,
                )
            else:
                with httpx.Client(timeout=self.timeout_seconds) as client:
                    response = client.request(
                        method,
                        url,
                        headers=headers,
                        **kwargs,
                    )
            response.raise_for_status()
        except (httpx.TimeoutException, httpx.NetworkError) as exc:
            raise KakaoRouteError("카카오 경로 API에 연결할 수 없습니다.") from exc
        except httpx.HTTPStatusError as exc:
            raise KakaoRouteError(
                f"카카오 경로 API가 HTTP {exc.response.status_code}를 반환했습니다."
            ) from exc

        try:
            return response.json()
        except ValueError as exc:
            raise KakaoRouteError(
                "카카오 경로 API가 JSON이 아닌 응답을 반환했습니다."
            ) from exc

    @staticmethod
    def _car_point(point: RoutePoint) -> dict[str, float | str]:
        return {
            "name": point.key,
            "x": point.longitude,
            "y": point.latitude,
        }

    @staticmethod
    def _car_legs(payload: Any) -> tuple[RouteLeg, ...]:
        try:
            route = payload["routes"][0]
            if route.get("result_code", 0) != 0:
                raise KakaoRouteError(
                    "카카오 자동차 경로를 찾을 수 없습니다: "
                    f"{route.get('result_msg') or route.get('result_message')}"
                )
            sections = route["sections"]
            return tuple(
                RouteLeg(
                    duration_seconds=int(section["duration"]),
                    distance_m=int(section["distance"]),
                )
                for section in sections
            )
        except KakaoRouteError:
            raise
        except (AttributeError, KeyError, IndexError, TypeError, ValueError) as exc:
            raise KakaoRouteError(
                "카카오 자동차 경로 응답 형식이 올바르지 않습니다."
            ) from exc

    @staticmethod
    def _walk_legs(payload: Any) -> tuple[RouteLeg, ...]:
        try:
            if payload["status"] != "OK":
                raise KakaoRouteError(
                    f"카카오 도보 경로를 찾을 수 없습니다: {payload['status']}"
                )
            return tuple(
                RouteLeg(
                    duration_seconds=int(leg["properties"]["time"]),
                    distance_m=int(leg["properties"]["distance"]),
                )
                for leg in payload["route"]["legs"]
            )
        except KakaoRouteError:
            raise
        except (KeyError, TypeError, ValueError) as exc:
            raise KakaoRouteError(
                "카카오 도보 경로 응답 형식이 올바르지 않습니다."
            ) from exc
