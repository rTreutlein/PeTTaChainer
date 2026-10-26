import re
import unittest

from pettachainer import PeTTaChainer


class TestPriorityRefinement(unittest.TestCase):
    def test_two_root_class_links_incorporate_late_case(self):
        # Fixed symmetric four-case population. Each class link is the
        # instance fold of its implication, so a late case reaches both
        # directions: at convergence both are 1/2 over two antecedent members.
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
                        f"(: {field}-{name} (Member sample-{name} {concept}) "
                        f"(STV {value} 1.0))"
                    )

        def parse_answer(answer):
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

        def truth_values(batches):
            self.assertEqual([len(batch) for batch in batches], [1, 1])
            values = []
            for batch in batches:
                answer = parse_answer(batch[0])
                self.assertEqual(answer[1], ["implication-instance-fold", "cpu"])
                values.append((float(answer[3][1]), float(answer[3][2])))
            return values

        two = 2 / 802
        for order in ("abc", "cba"):
            with self.subTest(order=order):
                chainer = PeTTaChainer()
                add_cases(chainer, order)
                initial = truth_values(chainer.query_many(roots, steps=80, timeout_sec=0))
                self.assertAlmostEqual(initial[0][0], 0.5, delta=1e-10)
                self.assertAlmostEqual(initial[0][1], two, delta=1e-10)
                self.assertAlmostEqual(initial[1][0], 1.0, delta=1e-10)
                self.assertAlmostEqual(initial[1][1], 1 / 801, delta=1e-10)

                add_cases(chainer, "d")
                refined = truth_values(chainer.query_many(roots, steps=320, timeout_sec=0))
                for strength, confidence in refined:
                    self.assertAlmostEqual(strength, 0.5, delta=1e-10)
                    self.assertAlmostEqual(confidence, two, delta=1e-10)


if __name__ == "__main__":
    unittest.main()
