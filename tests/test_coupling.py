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
            "runtime/backward/upward.metta": "(= (read-one) (compile ambiguous))\n"
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
            ("Compiler", "Executor"): ["read-one", "read-two"],
            ("Core types", "Executor"): ["read-one"],
            ("Executor", "Compiler"): ["compile"],
        })
        self.assertEqual(report["subsystem_edges"], 4)
        self.assertEqual(report["cross_functions"], 5)
        self.assertEqual(report["two_way_pairs"], 1)
        self.assertEqual(report["two_way"], [("Compiler", "Executor")])
        self.assertEqual((report["widest_interface"], report["widest_subsystem"]), (2, "Executor"))

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

    def test_function_cycles_within_subsystems_and_across_files(self):
        sources = {
            "compiler/first.metta": '(= (alpha) (beta leaf compile))\n'
                                    '(= (gamma) (alpha))\n'
                                    '(= (delta) (epsilon))\n'
                                    '(= (epsilon) (delta))\n'
                                    '(= (leaf) "parentheses ) (")\n'
                                    '(: leaf (-> alpha Atom))\n'
                                    '; (= (leaf) (alpha))\n',
            "compiler/second.metta": '(= (beta) True)\n(= (beta)\n (gamma))\n'
                                     '(= (alone) (alone))\n',
            "prolog/first.pl": "first(X) :- ( X = 1 -> true ; second(X) ).\n"
                               "% first(X) :- hidden(X).\n"
                               "/* first(X) :- hidden(X). */\n",
            "prolog/second.pl": "second(X) :- X = 'a. )', first(X).\n"
                                "second(X) :- X = 1.5.\n",
        }
        for name, source in sources.items():
            path = self.repo / "pettachainer/metta" / name
            path.write_text(source)
        subprocess.run(["git", "-C", str(self.repo), "add", "."], check=True,
                       stdin=subprocess.DEVNULL)
        subprocess.run(["git", "-C", str(self.repo), "-c", "user.name=test",
                        "-c", "user.email=test@example.invalid", "commit", "-qm", "cycles"],
                       check=True, stdin=subprocess.DEVNULL)
        report = coupling.measure(self.repo)
        nodes = {node["id"]: node for node in report["nodes"]}
        self.assertEqual(report["largest_function_scc"], 3)
        self.assertEqual(report["functions_in_cycles"], 10)
        self.assertEqual(report["largest_function_scc_members"], ["alpha", "beta", "gamma"])
        self.assertEqual(nodes["Compiler"]["largest_function_scc"], 3)
        self.assertEqual(nodes["Compiler"]["functions_in_cycles"], 5)
        self.assertEqual(nodes["Compiler"]["largest_function_scc_members"], ["alpha", "beta", "gamma"])
        self.assertEqual(nodes["Native stores"]["largest_function_scc_members"], ["first", "second"])
        self.assertEqual(nodes["Native stores"]["functions_in_cycles"], 2)
        for group in ("Executor", "Core types"):
            self.assertEqual(nodes[group]["largest_function_scc"], 0)
            self.assertEqual(nodes[group]["functions_in_cycles"], 0)
            self.assertEqual(nodes[group]["largest_function_scc_members"], [])

    def test_text_reports_subsystem_function_members(self):
        done = subprocess.run([sys.executable, str(Path(coupling.__file__))],
                              cwd=self.repo, stdin=subprocess.DEVNULL,
                              capture_output=True, text=True, check=True)
        self.assertIn("Function cycles: largest SCC 3, 3 functions in cycles", done.stdout)
        self.assertIn("Native stores: largest function SCC 0, 0 functions in cycles; members: (none)",
                      done.stdout)


if __name__ == "__main__":
    unittest.main()
