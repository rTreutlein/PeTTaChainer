"""Keep synthetic cache rows and a deliberate runtime fault out of other tests."""
import subprocess
import sys
import unittest
from pathlib import Path


class ExclusionStateTests(unittest.TestCase):
    def test_cut_recording_and_interruption_in_fresh_runtime(self):
        result = subprocess.run(
            [sys.executable, str(Path(__file__).parent / 'probes' / 'exclusion_state.py')],
            capture_output=True, text=True, timeout=60,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
