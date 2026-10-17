"""Keep the cold/warm implication regression in its own PeTTa runtime."""
import subprocess
import sys
import unittest
from pathlib import Path


class EmpiricalConditionalHistoryTests(unittest.TestCase):
    def test_cold_repeat_and_warm_at_both_budgets(self):
        result = subprocess.run(
            [sys.executable, str(Path(__file__).parent / 'probes' / 'empirical_conditional_history.py')],
            capture_output=True, text=True, timeout=120,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
