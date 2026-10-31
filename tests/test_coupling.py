"""Coupling counts committed lexical references across subsystem boundaries."""

import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from scripts import coupling


class Coupling(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.repo = Path(scratch.name)
        subprocess.run(["git", "init", "-q", str(self.repo)], check=True,
                       stdin=subprocess.DEVNULL)
        sources = {
            "compiler/compile.metta": "(= (compile) (read-one read-two read-one core-value))\n"
                                      "(= (ambiguous) True)\n; hidden\n",
            "runtime/forward/rules.metta": "(= (read-one) (compile ambiguous))\n"
                                           "(= (read-two) True)\n",
            "core/types.metta": "(= core-value (read-one))\n(= (ambiguous) False)\n",
            "prolog/runtime_state.pl": "hidden(X) :- hidden(X). % compile\n",
        }
        for name, source in sources.items():
            path = self.repo / "pettachainer/metta" / name
            path.parent.mkdir(parents=True, exist_ok=True)
            path.write_text(source)
        subprocess.run(["git", "-C", str(self.repo), "add", "."], check=True,
                       stdin=subprocess.DEVNULL)
        subprocess.run(["git", "-C", str(self.repo), "-c", "user.name=test",
                        "-c", "user.email=test@example.invalid", "commit", "-qm", "fixture"],
                       check=True, stdin=subprocess.DEVNULL)

    def test_two_way_pair_and_union_of_interface_functions(self):
        report = coupling.measure(self.repo)
        edges = {(edge["from"], edge["to"]): edge["functions"] for edge in report["edges"]}
        self.assertEqual(edges, {
            ("Compiler", "Core types"): ["core-value"],
            ("Compiler", "Forward"): ["read-one", "read-two"],
            ("Core types", "Forward"): ["read-one"],
            ("Forward", "Compiler"): ["compile"],
        })
        self.assertEqual(report["subsystem_edges"], 4)
        self.assertEqual(report["cross_functions"], 5)
        self.assertEqual(report["two_way_pairs"], 1)
        self.assertEqual(report["two_way"], [("Compiler", "Forward")])
        self.assertEqual((report["widest_interface"], report["widest_subsystem"]), (2, "Forward"))

    def test_cli_default_and_explicit_revision_ignore_working_tree(self):
        original = coupling.measure(self.repo)
        path = self.repo / "pettachainer/metta/compiler/compile.metta"
        path.write_text("(= (compile) True)\n")
        subprocess.run(["git", "-C", str(self.repo), "add", "."], check=True,
                       stdin=subprocess.DEVNULL)
        for args in (["--json"], ["HEAD", "--json"]):
            with self.subTest(args=args):
                done = subprocess.run([sys.executable, str(Path(coupling.__file__)), *args],
                                      cwd=self.repo, stdin=subprocess.DEVNULL,
                                      capture_output=True, text=True, check=True)
                self.assertEqual(json.loads(done.stdout), json.loads(json.dumps(original)))


if __name__ == "__main__":
    unittest.main()
