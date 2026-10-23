"""Tracker #15: assuming a disjunction does not select a certain disjunct."""
import unittest

from pettachainer import PeTTaChainer


class TestOrJudgments(unittest.TestCase):
    def test_ordinary_or_with_negated_or_computed_disjunct(self):
        # #85: such an Or was modus ponens over the conjunction of its disjuncts.
        h = PeTTaChainer()
        h.add_atoms_no_check(['(: q1 (Q x) (STV 0.6 0.9))', '(: r1 (R x) (STV 0.5 0.9))',
                              '(: n1 (Num x 3) (STV 1 1))'])
        fold = '(FoldAllTruth (Num $o $n) (STV $s $c) $s 0 (|-> ($acc $e) (+ $acc $e)) -> $t)'
        for goal, strength in (('(Or (Q x) (Not (R x)))', 0.8), ('(Or (Not (R x)) (Q x))', 0.8),
                               ('(Or (Q x) (Not (Q x)))', 1.0), (f'(Or (Q x) {fold})', 1.0),
                               ('(And (Q x) (Not (R x)))', 0.3)):
            with self.subTest(goal=goal):
                rows = h.query_many_refs([f'(: $p {goal} $tv)'], steps=300)[0]
                self.assertEqual(len(rows), 1, rows)
                self.assertAlmostEqual(rows[0].tv[1], strength)

    def test_missing_disjunction_prior_is_unknown(self):
        # Exact tracker example: without P(A or C), the A -> B rule alone
        # cannot justify treating A as certain in an Or judgment.
        h = PeTTaChainer()
        h.add_atoms_no_check(['(: rule (Implication A B) (STV 0.3 0.9))'])
        for repeat in range(2):
            with self.subTest(repeat=repeat):
                self.assertEqual(h.query_many_refs([
                    '(: $p (Implication (Or A C) B) $tv)',
                ], steps=300)[0], [])
        self.assertEqual(h.query_many_refs([
            '(: $p A $tv)', '(: $p C $tv)', '(: $p B $tv)',
        ], steps=300), [[], [], []])

    def test_disjunct_is_conditioned_on_disjunction(self):
        for order in (('(A $x)', '(C $x)'), ('(C $x)', '(A $x)')):
            h = PeTTaChainer()
            h.add_atoms_no_check([
                '(: rule (Implication (A $x) (B $x)) (CTV (STV 0.3 0.9) (STV 0.1 0.9)))',
            ])
            h._call('set-base-rate', [f'{h.kb} (A $x) (STV 0.2 1)'])
            h._call('set-base-rate', [f'{h.kb} (C $x) (STV 0.4 1)'])
            h._call('set-base-rate', [f"{h.kb} (Or {' '.join(order)}) (STV 0.52 1)"])
            expression = '(Implication (Or ' + ' '.join(order) + ') (B $x))'
            for repeat in range(2):
                with self.subTest(order=order, repeat=repeat):
                    rows = h.query_many_refs([f'(: $p {expression} $tv)'], steps=300)[0]
                    self.assertEqual(len(rows), 1, rows)
                    self.assertAlmostEqual(rows[0].tv[1], 0.1 + 0.2 * (0.2 / 0.52))
                    self.assertGreater(rows[0].tv[2], 0)
            control = PeTTaChainer()
            control.add_atoms_no_check([
                '(: rule (Implication (A $x) (B $x)) (CTV (STV 0.3 0.9) (STV 0.1 0.9)))',
            ])
            control._call('set-base-rate', [f'{control.kb} (A $x) (STV 0.2 1)'])
            control._call('set-base-rate', [f'{control.kb} (C $x) (STV 0.4 1)'])
            control._call('set-base-rate', [f"{control.kb} (Or {' '.join(order)}) (STV 0.52 1)"])
            goals = ['(: $p (A item) $tv)', '(: $p (C item) $tv)', '(: $p (B item) $tv)']
            actual = h.query_many_refs(goals, steps=300)
            expected = control.query_many_refs(goals, steps=300)
            self.assertEqual([[r.tv for r in rows] for rows in actual],
                             [[r.tv for r in rows] for rows in expected])
            for rows in actual:
                for row in rows:
                    self.assertNotIn('(ctx proof ', h.expand_proof(row.proof))

    def test_joint_and_compound_conditioning(self):
        # Each case has independent Bernoulli priors. A conjunction consumer
        # must use P(A and C | A or C), not multiply conditional marginals.
        cases = [
            ('(Or (A $x) (C $x))', '(A $x)', 0.2 / 0.52),
            ('(Or (C $x) (A $x))', '(A $x)', 0.2 / 0.52),
            ('(Or (A $x) (C $x))', '(And (A $x) (C $x))', 0.08 / 0.52),
            ('(Or (A $x) (C $x) (E $x))', '(A $x)', 0.2 / 0.76),
            ('(And (G $x) (Or (A $x) (C $x)))', '(And (G $x) (A $x))', 0.2 / 0.52),
            ('(Not (Not (Or (A $x) (C $x))))', '(A $x)', 0.2 / 0.52),
            ('(Or (Not (A $x)) (C $x))', '(Not (A $x))', 0.8 / 0.88),
        ]
        for antecedent, premise, expected in cases:
            for ground in (False, True):
                h = PeTTaChainer()
                h.add_atoms_no_check([
                    f'(: (no_inverse rule) (Implication {premise} (B $x)) (CTV (STV 1 1) (STV 0 1)))',
                ])
                rates = {'(A $x)': 0.2, '(C $x)': 0.4, '(E $x)': 0.5,
                         '(Or (A $x) (C $x))': 0.52, '(Or (C $x) (A $x))': 0.52,
                         '(Or (A $x) (C $x) (E $x))': 0.76,
                         '(Or (Not (A $x)) (C $x))': 0.88}
                for pattern, strength in rates.items():
                    if ground:
                        pattern = pattern.replace('$x', 'item')
                    h._call('set-base-rate', [f'{h.kb} {pattern} (STV {strength} 1)'])
                expression = f'(Implication {antecedent} (B $x))'
                if ground:
                    expression = expression.replace('$x', 'item')
                for repeat in range(2):
                    with self.subTest(antecedent=antecedent, premise=premise, ground=ground, repeat=repeat):
                        rows = h.query_many_refs([f'(: $p {expression} $tv)'], steps=1000)[0]
                        self.assertEqual(len(rows), 1, rows)
                        self.assertAlmostEqual(rows[0].tv[1], expected)
                        self.assertGreater(rows[0].tv[2], 0)
                        self.assertIn('(ctx proof ', h.expand_proof(rows[0].proof))
                # Inference can return a population prior; categorical facts
                # and assumption provenance must never be published in MAIN.
                for atom in ('(A item)', '(C item)', '(B item)'):
                    self.assertEqual(h._call('collapse', [
                        f'(match &kb ({atom} ({h.kb} MAIN Nil) $p $tv) leaked)']), ['()'])

    def test_world_only_consequent_cannot_supply_conditional(self):
        for confidence in (0.9, 1):
            h = PeTTaChainer()
            h.add_atoms_no_check([
                f'(: world (B item) (STV 1 {confidence}))',
                '(: c (Recorded R) (STV 1 0.9))',
                '(: (no_inverse rule) (Implication (Recorded R) (B item)) (STV 1 0.9))',
            ])
            for _ in range(2):
                self.assertEqual(h.query_many_refs([
                    '(: $p (Implication (Or (A item) (C item)) (B item)) $tv)',
                ], steps=300)[0], [])

    def test_disjunct_and_impossible_event(self):
        for a, c, event in ((0.2, 0.4, 0.52), (0, 0, 0)):
            h = PeTTaChainer()
            for pattern, strength in (('(A $x)', a), ('(C $x)', c),
                                      ('(Or (A $x) (C $x))', event)):
                h._call('set-base-rate', [f'{h.kb} {pattern} (STV {strength} 1)'])
            for repeat in range(2):
                with self.subTest(event=event, repeat=repeat):
                    rows = h.query_many_refs([
                        '(: $p (Implication (Or (A $x) (C $x)) (A $x)) $tv)',
                    ], steps=300)[0]
                    if event == 0:
                        self.assertEqual(rows, [])
                    else:
                        self.assertEqual(len(rows), 1, rows)
                        self.assertAlmostEqual(rows[0].tv[1], a / event)
