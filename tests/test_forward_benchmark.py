from __future__ import annotations

import unittest
from unittest.mock import patch

from pettachainer.benchmarks import forward_vs_backward as benchmark


class ForwardBenchmarkTests(unittest.TestCase):
    def test_missing_forward_work_cannot_be_hidden_by_backward_search(self) -> None:
        with patch.object(benchmark.PeTTaChainer, "forward_chain", return_value=[]):
            for run in (
                lambda: benchmark.time_forward_goal(depth=1, noise_branching=1),
                lambda: benchmark.time_forward_full(
                    depth=1, noise_branching=1, full_steps=3
                ),
            ):
                with self.subTest(run=run), self.assertRaisesRegex(
                    ValueError, "No canonical KB fact"
                ):
                    run()


if __name__ == "__main__":
    unittest.main()
