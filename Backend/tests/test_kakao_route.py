import os

os.environ.setdefault("DATABASE_URL", "sqlite://")
os.environ.setdefault("GOOGLE_CLIENT_ID", "test.apps.googleusercontent.com")
os.environ.setdefault("KAKAO_APP_ID", "1234")
os.environ.setdefault("JWT_SECRET_KEY", "test-only-secret-key-with-32-characters")

import httpx
import pytest

from api.scheduler.models import MobilityMode
from api.scheduler.route_optimizer import RoutePoint
from infra.kakao_route import KakaoRouteClient, KakaoRouteError, RouteLeg


def route() -> tuple[RoutePoint, ...]:
    return (
        RoutePoint("origin", 37.50, 127.00),
        RoutePoint("stop-1", 37.51, 127.01),
        RoutePoint("stop-2", 37.52, 127.02),
    )


def test_car_route_uses_one_request_and_parses_each_section() -> None:
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(
            200,
            json={
                "routes": [
                    {
                        "result_code": 0,
                        "sections": [
                            {"duration": 120, "distance": 1_000},
                            {"duration": 240, "distance": 2_000},
                        ],
                    }
                ]
            },
        )

    with httpx.Client(transport=httpx.MockTransport(handler)) as http_client:
        client = KakaoRouteClient(rest_api_key="test-key", client=http_client)
        legs = client.verify(MobilityMode.CAR, route())

    assert legs == (RouteLeg(120, 1_000), RouteLeg(240, 2_000))
    assert len(requests) == 1
    assert requests[0].method == "POST"
    assert b'"summary":false' in requests[0].content
    assert b'"waypoints":[{"name":"stop-1"' in requests[0].content


def test_walk_route_uses_one_request_and_parses_each_leg() -> None:
    requests: list[httpx.Request] = []

    def handler(request: httpx.Request) -> httpx.Response:
        requests.append(request)
        return httpx.Response(
            200,
            json={
                "status": "OK",
                "route": {
                    "legs": [
                        {"properties": {"time": 300, "distance": 400}},
                        {"properties": {"time": 600, "distance": 800}},
                    ]
                },
            },
        )

    with httpx.Client(transport=httpx.MockTransport(handler)) as http_client:
        client = KakaoRouteClient(rest_api_key="test-key", client=http_client)
        legs = client.verify(MobilityMode.WALK, route())

    assert legs == (RouteLeg(300, 400), RouteLeg(600, 800))
    assert len(requests) == 1
    assert requests[0].method == "GET"
    assert requests[0].url.params["via_x"] == "127.01"
    assert requests[0].url.params["via_y"] == "37.51"


def test_rejects_response_with_wrong_leg_count() -> None:
    def handler(request: httpx.Request) -> httpx.Response:
        del request
        return httpx.Response(
            200,
            json={"status": "OK", "route": {"legs": []}},
        )

    with httpx.Client(transport=httpx.MockTransport(handler)) as http_client:
        client = KakaoRouteClient(rest_api_key="test-key", client=http_client)
        with pytest.raises(KakaoRouteError, match="다른 구간 수"):
            client.verify(MobilityMode.WALK, route())
