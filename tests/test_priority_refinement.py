import re
import unittest

from pettachainer import PeTTaChainer


class TestPriorityRefinement(unittest.TestCase):
    def test_two_root_inheritance_incorporates_late_case(self):
        # Fixed symmetric four-case population. At convergence both directions
        # have the same TV; each hypothetical context must include every case.
        cases = {"a": (1.0, 0.0), "b": (1.0, 1.0),
                 "c": (0.0, 0.0), "d": (0.0, 1.0)}
        roots = [
            "(: $proof (Inheritance Observed Outcome) $tv)",
            "(: $proof (Inheritance Outcome Observed) $tv)",
        ]

        def add_cases(chainer, names):
            for name in names:
                for field, concept, value in zip(
                    ("observed", "outcome"), ("Observed", "Outcome"), cases[name]
                ):
                    chainer.add_atom(
                        f"(: {field}-{name} (Inheritance sample-{name} {concept}) "
                        f"(STV {value} 1.0))"
                    )

        def parse_answer(answer):
            # Parse the public proof tree so an incidental occurrence of d
            # inside a calibration fold cannot masquerade as a context witness.
            stack = [[]]
            for token in re.findall(r"[()]|[^\s()]+", answer):
                if token == "(":
                    stack.append([])
                elif token == ")":
                    node = stack.pop()
                    stack[-1].append(node)
                else:
                    stack[-1].append(token)
            self.assertEqual(len(stack), 1)
            self.assertEqual(len(stack[0]), 1)
            return stack[0][0]

        for order in ("abc", "cba"):
            with self.subTest(order=order):
                chainer = PeTTaChainer()
                add_cases(chainer, order)
                initial = chainer.query_many(roots, steps=80, timeout_sec=0)
                self.assertEqual([len(batch) for batch in initial], [1, 1])

                add_cases(chainer, "d")
                refined = chainer.query_many(roots, steps=320, timeout_sec=0)
                self.assertEqual([len(batch) for batch in refined], [1, 1])
                for root, batch in enumerate(refined):
                    answer = parse_answer(batch[0])
                    proof, tv = answer[1], answer[3]
                    with self.subTest(root=root, check="truth value"):
                        self.assertEqual(tv[0], "STV")
                        # Fixed reference, compared numerically rather
                        # than by string formatting.
                        self.assertAlmostEqual(
                            float(tv[1]), 0.4997335746440823, delta=1e-10
                        )
                        self.assertAlmostEqual(
                            float(tv[2]), 3.999988000035998e-06, delta=1e-10
                        )
                    self.assertEqual(proof[0], "inheritance-implication-fold")
                    self.assertEqual(proof[1][0], "total-implication")
                    self.assertEqual(len(proof[1][1:]), 2)
                    for context, branch in enumerate(proof[1][1:]):
                        with self.subTest(root=root, context=context):
                            pending, witnesses = [branch], []
                            while pending:
                                node = pending.pop()
                                if node[0] == "merge/revision":
                                    pending.extend(node[1:])
                                else:
                                    self.assertEqual(node[0], "by")
                                    self.assertEqual(node[1][0], "inheritance-implication")
                                    witnesses.append(node[1][1])
                            field = ("outcome", "observed")[root]
                            self.assertCountEqual(
                                witnesses, [f"{field}-{name}" for name in "abcd"]
                            )
