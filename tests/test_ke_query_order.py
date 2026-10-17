"""A prior judgment must not suppress an independently supported judgment."""
import json
from pathlib import Path
import re
import subprocess
import sys
import unittest


class KEQueryOrderTests(unittest.TestCase):
    def test_announcement_after_conditional_queries_and_retained_history(self):
        probe = Path(__file__).parent / "probes" / "ke_query_order.py"
        expected = None
        for scenario in ("cold", "warm", "cold-diag", "warm-diag", "history"):
            with self.subTest(scenario=scenario):
                run = subprocess.run([sys.executable, str(probe), scenario],
                                     text=True, capture_output=True, timeout=90)
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)
                result = json.loads(run.stdout.splitlines()[-1])
                proofs = result["proofs"]
                self.assertEqual(len(proofs), 1, result)
                self.assertTrue(proofs[0].endswith("(STV 1.0 0.9996501223478415))"), proofs)
                self.assertEqual(set(re.findall(r"src_[0-9a-f]+", proofs[0])), {
                    "src_d2acc8331d260378be524a14", "src_acb3faeae7e53c5cf8a75bc7",
                    "src_6c4b43ffc9cfdd9f6cc82137",
                })
                # A fresh judgment allocates a fresh assumption world. Its
                # local number is not evidence; preserve the complete rest
                # of the proof, including every source and projection.
                normalized = [re.sub(r"\(ctx proof \d+\)", "(ctx proof WORLD)", p) for p in proofs]
                if expected is None:
                    expected = normalized
                self.assertEqual(normalized, expected)
                if scenario == "history":
                    self.assertEqual(len(result["history_counts"]), 10)
                    self.assertEqual(result["history_counts"][6], [1, 0])
