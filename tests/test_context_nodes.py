"""Keep the issue #60 history/permutation campaign in a fresh SWI runtime."""
import subprocess
import sys
import unittest
from pathlib import Path


class ContextNodeRoundZeroTests(unittest.TestCase):
    def test_acceptance_probes(self):
        result = subprocess.run(
            [sys.executable, str(Path(__file__).parent / 'probes/context_nodes.py')],
            capture_output=True, text=True, timeout=600,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
