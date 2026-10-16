"""Tracker #16: assumption polarity is the parity of every enclosing Not."""
import unittest

from pettachainer import PeTTaChainer


class TestNestedNotJudgments(unittest.TestCase):
    def test_nested_polarities_fresh_and_warm(self):
        for depth in (2, 3, 4, 5):
            for term in ('(A x)', '(A $x)'):
                h = PeTTaChainer()
                h.add_atoms_no_check([
                    '(: rule (Implication (A $v) (B $v)) (CTV (STV 0.8 0.9) (STV 0.2 0.9)))',
                    '(: world (A x) (STV 0.4 0.8))',
                ])
                antecedent = term
                for _ in range(depth):
                    antecedent = f'(Not {antecedent})'
                consequent = term.replace('A ', 'B ')
                query = f'(Implication {antecedent} {consequent})'
                for repeat in range(2):
                    with self.subTest(depth=depth, term=term, repeat=repeat):
                        rows = h.query_many_refs([f'(: $p {query} $tv)'], steps=300)[0]
                        self.assertEqual(len(rows), 1, rows)
                        self.assertAlmostEqual(rows[0].tv[1], 0.8 if depth % 2 == 0 else 0.2)
                        self.assertGreater(rows[0].tv[2], 0)
                        proof = h.expand_proof(rows[0].proof)
                        self.assertIn('(ctx proof ', proof)
                        self.assertNotIn('world', proof)
                # Compare warmed MAIN with a KB that never opened a judgment.
                control = PeTTaChainer()
                control.add_atoms_no_check([
                    '(: rule (Implication (A $v) (B $v)) (CTV (STV 0.8 0.9) (STV 0.2 0.9)))',
                    '(: world (A x) (STV 0.4 0.8))',
                ])
                for goal in ('(A x)', '(B x)'):
                    values = [kb.query_many_refs([f'(: $p {goal} $tv)'], steps=300)[0]
                              for kb in (h, control)]
                    self.assertEqual([r.tv for r in values[0]], [r.tv for r in values[1]])

    def test_no_categorical_assumption_or_consequent(self):
        h = PeTTaChainer()
        h.add_atoms_no_check(['(: rule (Implication (A $v) (B $v)) (STV 0.8 0.9))'])
        for _ in range(2):
            self.assertTrue(h.query_many_refs([
                '(: $p (Implication (Not (Not (A x))) (B x)) $tv)',
            ], steps=300)[0])
        self.assertEqual(h.query_many_refs([
            '(: $p (A x) $tv)', '(: $p (Not (A x)) $tv)', '(: $p (B x) $tv)',
        ], steps=300), [[], [], []])
