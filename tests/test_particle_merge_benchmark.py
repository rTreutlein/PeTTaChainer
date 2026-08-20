from __future__ import annotations

import importlib.util
import math
import sys
import unittest
from pathlib import Path


REPO_ROOT = Path(__file__).resolve().parents[1]
BENCHMARK_PATH = (
    REPO_ROOT
    / "pettachainer"
    / "benchmarks"
    / "particle_merge_resampling.py"
)
BENCHMARK_DIRECTORY = BENCHMARK_PATH.parent
SPEC = importlib.util.spec_from_file_location(
    "particle_merge_resampling", BENCHMARK_PATH
)
if SPEC is None or SPEC.loader is None:
    raise RuntimeError(f"cannot load benchmark module: {BENCHMARK_PATH}")
BENCHMARK = importlib.util.module_from_spec(SPEC)
sys.path.insert(0, str(BENCHMARK_DIRECTORY))
sys.modules[SPEC.name] = BENCHMARK
try:
    SPEC.loader.exec_module(BENCHMARK)
finally:
    sys.path.pop(0)


class ParticleMergeBenchmarkTests(unittest.TestCase):
    def test_order_variants_preserve_the_same_generated_points(self) -> None:
        points = BENCHMARK.generate_points(32, 7)
        clustered = BENCHMARK.ordered_points(points, "clustered", 7)
        shuffled = BENCHMARK.ordered_points(points, "shuffled", 7)

        self.assertEqual(set(clustered), set(shuffled))
        self.assertNotEqual(clustered, shuffled)

    def test_incremental_expression_uses_distribution_state(self) -> None:
        expression = BENCHMARK.incremental_expression(
            BENCHMARK.generate_points(4, 3), 2
        )

        self.assertIn("fold-flat benchmark-particle-add", expression)
        self.assertIn("BenchmarkParticleState", expression)
        self.assertNotIn("ParticleFromPairs", expression)
        self.assertEqual(expression.count("BenchmarkPoint"), 4)

    def test_parse_and_validate_particle_pairs(self) -> None:
        pairs = BENCHMARK.parse_particle_pairs(
            [
                "(((BenchmarkPoint 1.0 -2.0) 0.25) "
                "((BenchmarkPoint 3.0 4.0) 0.75))"
            ]
        )

        self.assertEqual(pairs, [(1.0, -2.0, 0.25), (3.0, 4.0, 0.75)])
        BENCHMARK.validate_result(pairs, 2)

    def test_quality_is_zero_for_an_uncompressed_distribution(self) -> None:
        points = [
            BENCHMARK.Point(1.0, 2.0, 0),
            BENCHMARK.Point(3.0, 4.0, 1),
        ]
        compressed = [(1.0, 2.0, 0.5), (3.0, 4.0, 0.5)]

        quality = BENCHMARK.quality_metrics(points, compressed)

        self.assertTrue(
            all(math.isclose(value, 0.0) for value in quality.values())
        )

    def test_summary_rejects_nondeterministic_particles(self) -> None:
        first = {
            "seconds": 1.0,
            "points_per_second": 4.0,
            "peak_rss_kib": 10,
            "support": 2,
            "mass": 1.0,
            "digest": "first",
            "quality": {"mean_l2_error": 0.0},
        }
        second = {**first, "digest": "second"}

        with self.assertRaisesRegex(
            BENCHMARK.ParticleMergeBenchmarkError,
            "different particle distributions",
        ):
            BENCHMARK.summarize_workload([first, second])


if __name__ == "__main__":
    unittest.main()
