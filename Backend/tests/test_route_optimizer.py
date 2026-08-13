import math
import unittest

from api.scheduler.route_optimizer import (
    GeodesicCostProvider,
    RouteOptimizer,
    RoutePoint,
    haversine_distance_m,
    optimize_geodesic_route,
)


class MatrixCostProvider:
    unit = "second"

    def __init__(self, costs: dict[tuple[str, str], float]) -> None:
        self.costs = costs

    def cost(self, start: RoutePoint, end: RoutePoint) -> float:
        return self.costs[(start.key, end.key)]


class RoutePointTests(unittest.TestCase):
    def test_rejects_invalid_coordinate_or_empty_key(self) -> None:
        invalid_points = (
            ("", 37.0, 127.0),
            ("x", 91.0, 127.0),
            ("x", 37.0, -181.0),
            ("x", math.nan, 127.0),
        )

        for key, latitude, longitude in invalid_points:
            with self.subTest(
                key=key,
                latitude=latitude,
                longitude=longitude,
            ), self.assertRaises(ValueError):
                RoutePoint(key, latitude, longitude)


class GeodesicCostProviderTests(unittest.TestCase):
    def test_haversine_distance_matches_known_seoul_busan_scale(self) -> None:
        seoul = RoutePoint("seoul", 37.5665, 126.9780)
        busan = RoutePoint("busan", 35.1796, 129.0756)

        distance = haversine_distance_m(seoul, busan)

        self.assertGreater(distance, 320_000)
        self.assertLess(distance, 330_000)
        self.assertAlmostEqual(
            distance,
            GeodesicCostProvider().cost(seoul, busan),
        )


class RouteOptimizerTests(unittest.TestCase):
    def setUp(self) -> None:
        self.origin = RoutePoint("origin", 0.0, 0.0)
        self.a = RoutePoint("a", 0.0, 1.0)
        self.b = RoutePoint("b", 0.0, 2.0)
        self.c = RoutePoint("c", 0.0, 3.0)
        self.d = RoutePoint("d", 0.0, 4.0)

    def test_returns_every_stop_once_without_mutating_input(self) -> None:
        stops = [self.c, self.a, self.b]
        original = list(stops)

        result = optimize_geodesic_route(self.origin, stops)

        self.assertEqual(stops, original)
        self.assertEqual([point.key for point in result.route], ["origin", "a", "b", "c"])
        self.assertCountEqual(
            [point.key for point in result.ordered_stops],
            ["a", "b", "c"],
        )
        self.assertEqual(result.cost_unit, "meter")
        self.assertLessEqual(result.optimized_cost, result.seed_cost)

    def test_tie_breaking_follows_input_order(self) -> None:
        north = RoutePoint("north", 1.0, 0.0)
        east = RoutePoint("east", 0.0, 1.0)

        result = optimize_geodesic_route(
            self.origin,
            [east, north],
            max_two_opt_passes=0,
        )

        self.assertEqual([point.key for point in result.ordered_stops], ["east", "north"])

    def test_two_opt_improves_directed_seed_route(self) -> None:
        costs = {
            ("origin", "a"): 1,
            ("origin", "b"): 20,
            ("origin", "c"): 20,
            ("origin", "d"): 20,
            ("a", "b"): 1,
            ("a", "c"): 2,
            ("a", "d"): 3,
            ("b", "a"): 20,
            ("b", "c"): 1,
            ("b", "d"): 2,
            ("c", "a"): 20,
            ("c", "b"): 1,
            ("c", "d"): 10,
            ("d", "a"): 20,
            ("d", "b"): 2,
            ("d", "c"): 1,
        }
        optimizer = RouteOptimizer(MatrixCostProvider(costs))

        result = optimizer.optimize(self.origin, [self.a, self.b, self.c, self.d])

        self.assertEqual(result.seed_cost, 13)
        self.assertEqual(result.optimized_cost, 5)
        self.assertEqual(
            [point.key for point in result.ordered_stops],
            ["a", "b", "d", "c"],
        )
        self.assertGreaterEqual(result.two_opt_passes, 1)
        self.assertEqual(result.improvement, 8)

    def test_fixed_destination_is_preserved_in_route_and_cost(self) -> None:
        destination = RoutePoint("destination", 0.0, 5.0)

        result = optimize_geodesic_route(
            self.origin,
            [self.c, self.a, self.b, self.d],
            destination=destination,
        )

        self.assertEqual(result.route[0], self.origin)
        self.assertEqual(result.route[-1], destination)
        self.assertEqual(
            [point.key for point in result.ordered_stops],
            ["a", "b", "c", "d"],
        )

    def test_allows_round_trip_destination_equal_to_origin(self) -> None:
        result = optimize_geodesic_route(
            self.origin,
            [self.b, self.a],
            destination=self.origin,
        )

        self.assertEqual(result.route[0], self.origin)
        self.assertEqual(result.route[-1], self.origin)
        self.assertEqual(len(result.ordered_stops), 2)

    def test_rejects_duplicate_stop_keys(self) -> None:
        duplicate = RoutePoint("a", 1.0, 1.0)

        with self.assertRaisesRegex(ValueError, "중복"):
            optimize_geodesic_route(self.origin, [self.a, duplicate])

    def test_rejects_stop_key_matching_fixed_endpoint(self) -> None:
        duplicate_origin = RoutePoint("origin", 1.0, 1.0)
        duplicate_destination = RoutePoint("destination", 1.0, 1.0)
        destination = RoutePoint("destination", 2.0, 2.0)

        with self.assertRaisesRegex(ValueError, "출발지 key"):
            optimize_geodesic_route(self.origin, [duplicate_origin])
        with self.assertRaisesRegex(ValueError, "도착지 key"):
            optimize_geodesic_route(
                self.origin,
                [duplicate_destination],
                destination=destination,
            )

    def test_rejects_round_trip_key_with_different_coordinate(self) -> None:
        different_origin = RoutePoint("origin", 1.0, 1.0)

        with self.assertRaisesRegex(ValueError, "동일한 좌표"):
            optimize_geodesic_route(
                self.origin,
                [self.a],
                destination=different_origin,
            )

    def test_rejects_invalid_cost_provider_output(self) -> None:
        invalid_provider = MatrixCostProvider({("origin", "a"): math.inf})

        with self.assertRaisesRegex(ValueError, "경로 비용"):
            RouteOptimizer(invalid_provider).optimize(self.origin, [self.a])


if __name__ == "__main__":
    unittest.main()
