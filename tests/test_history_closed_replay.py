"""Isolate the temporal history fixture and its cache audit from other KBs."""
import subprocess
import sys
import unittest
from pathlib import Path


class ClosedHistoryReplayTests(unittest.TestCase):
    def test_closed_history_replay_in_fresh_runtime(self):
        result = subprocess.run(
            [sys.executable, str(Path(__file__).parent / 'probes/history_closed_replay.py')],
            capture_output=True, text=True, timeout=120,
        )
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
