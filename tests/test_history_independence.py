"""Run the cycle campaign without retaining its KBs in other tests' runtime."""
import subprocess
import sys
import unittest
from pathlib import Path


class HistoryIndependenceTests(unittest.TestCase):
    def test_c1_and_cycle_family_in_fresh_runtime(self):
        # PeTTa's durable KBs share a process. The permutation campaign builds
        # many of them; keep that history out of the GC phase tests' setup.
        result = subprocess.run(
            [sys.executable, str(Path(__file__).parent / 'probes' / 'history_independence.py')],
            capture_output=True, text=True, timeout=120,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
