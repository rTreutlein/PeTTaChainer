"""Tracker #72: compound negation and durable internal Or consumers."""
import unittest

from pettachainer import PeTTaChainer


class TestCompoundNotJudgments(unittest.TestCase):
    def test_internal_or_ctv_survives_queries(self):
        for public_first in (False, True):
            h = PeTTaChainer()
            h.add_atoms_no_check([
                '(: rule (Implication (A $x) (B $x)) (CTV (STV 0.3 0.9) (STV 0.1 0.9)))',
            ])
            for pattern, strength in (('(A $x)', 0.2), ('(C $x)', 0.4),
                                      ('(Or (A $x) (C $x))', 0.52)):
                h._call('set-base-rate', [f'{h.kb} {pattern} (STV {strength} 1)'])
            public = '(: $p (Implication (Or (A $x) (C $x)) (B $x)) $tv)'
            if public_first:
                self.assertTrue(h.query_many_refs([public], steps=1000)[0])
            h._call('kb-add-expr', [f'backward (rules ('
                f'(((Implication (Or (A $x) (C $x)) (B $x)) ({h.kb} MAIN Nil) $p (CTV $pos $neg)))'
                f' |- ((ReadCTV $x $neg) ({h.kb} MAIN Nil) (ctv-read $p) $pos)))'])
            for repeat in range(3):
                with self.subTest(public_first=public_first, repeat=repeat):
                    rows = h.query_many_refs(['(: $p (ReadCTV $x $neg) $tv)'], steps=1000)[0]
                    self.assertEqual(len(rows), 1, rows)
                    self.assertAlmostEqual(rows[0].tv[1], 0.1 + 0.2 * 0.2 / 0.52)
                    self.assertGreater(rows[0].tv[2], 0)
                    self.assertAlmostEqual(rows[0].statement[2][1], 0.1)
                    self.assertGreater(rows[0].statement[2][2], 0)
                    self.assertIn('(ctx proof ', h.expand_proof(rows[0].proof))
                # A public query creates and then removes its own scaffold.
                self.assertTrue(h.query_many_refs([public], steps=1000)[0])

    def test_batch_and_root_does_not_project_onto_a_sibling_root(self):
        # A batch's And root once projected its conjunction onto its Not
        # conjunct: (Not (Q x)) read P(not Q and R), 0.2, instead of 0.4.
        for order in (('(Not (Q x))', '(R x)'), ('(R x)', '(Not (Q x))')):
            h = PeTTaChainer()
            h.add_atoms_no_check(['(: q1 (Q x) (STV 0.6 0.9))', '(: r1 (R x) (STV 0.5 0.9))'])
            with self.subTest(order=order):
                rows = h.query_many_refs([f'(: $p (And {order[0]} {order[1]}) $tv)',
                                          '(: $p (Not (Q x)) $tv)'], steps=300)[1]
                self.assertEqual([r.tv[1:] for r in rows], [[0.4, 0.9]])

    def test_compound_negation(self):
        cases = [
            ('(Not (Or (A $x) (C $x)))', 0.1),
            ('(Not (And (A $x) (C $x)))', 0.1 + 0.2 * 0.12 / 0.92),
            ('(Not (Or (Not (A $x)) (C $x)))', 0.3),
            ('(Not (Not (Not (Or (A $x) (C $x)))))', 0.1),
            ('(Not (And (A $x) (Or (C $x) (E $x))))', 0.1 + 0.2 * 0.06 / 0.86),
            ('(And (G $x) (Not (And (A $x) (C $x))))', 0.1 + 0.2 * 0.12 / 0.92),
        ]
        for antecedent, expected in cases:
            for ground in (False, True):
                h = PeTTaChainer()
                premise = '(And (G $x) (A $x))' if antecedent.startswith('(And ') else '(A $x)'
                h.add_atoms_no_check([
                    f'(: rule (Implication {premise} (B $x)) (CTV (STV 0.3 0.9) (STV 0.1 0.9)))',
                    '(: world (B item) (STV 1 1))',
                ])
                for pattern, strength in (('(A $x)', 0.2), ('(C $x)', 0.4), ('(E $x)', 0.5),
                        ('(Not (Or (A $x) (C $x)))', 0.48),
                        ('(Not (And (A $x) (C $x)))', 0.92),
                        ('(Not (Or (Not (A $x)) (C $x)))', 0.12),
                        ('(Not (And (A $x) (Or (C $x) (E $x))))', 0.86)):
                    if ground:
                        pattern = pattern.replace('$x', 'item')
                    h._call('set-base-rate', [f'{h.kb} {pattern} (STV {strength} 1)'])
                expression = f'(Implication {antecedent} (B $x))'
                if ground:
                    expression = expression.replace('$x', 'item')
                for repeat in range(3):
                    with self.subTest(antecedent=antecedent, ground=ground, repeat=repeat):
                        rows = h.query_many_refs([f'(: $p {expression} $tv)'], steps=1000)[0]
                        self.assertEqual(len(rows), 1, rows)
                        self.assertAlmostEqual(rows[0].tv[1], expected)
                        self.assertGreater(rows[0].tv[2], 0)
                        proof = h.expand_proof(rows[0].proof)
                        self.assertIn('(ctx proof ', proof)
                        self.assertNotIn('world', proof)
                for atom in ('(A item)', '(C item)'):
                    self.assertEqual(h._call('collapse', [
                        f'(match &kb ({atom} ({h.kb} MAIN Nil) $p $tv) leaked)']), ['()'])

    def test_impossible_negated_compound(self):
        for event in ('(Not (Or (A $x) (C $x)))', '(Not (And (A $x) (C $x)))'):
            h = PeTTaChainer()
            h.add_atoms_no_check([
                '(: rule (Implication (A $x) (B $x)) (CTV (STV 0.3 0.9) (STV 0.1 0.9)))',
            ])
            for pattern, strength in (('(A $x)', 1), ('(C $x)', 1), (event, 0)):
                h._call('set-base-rate', [f'{h.kb} {pattern} (STV {strength} 1)'])
            for repeat in range(2):
                with self.subTest(event=event, repeat=repeat):
                    self.assertEqual(h.query_many_refs([
                        f'(: $p (Implication {event} (B $x)) $tv)',
                    ], steps=1000)[0], [])

    def test_whole_compound_consumer_without_priors(self):
        for connective in ('And', 'Or'):
            h = PeTTaChainer()
            event = f'(Not ({connective} (G) (H)))'
            h.add_atoms_no_check([
                f'(: world ({connective} (G) (H)) (STV 1 1))',
                f'(: rule (Implication {event} (Y)) (CTV (STV 0.9 0.9) (STV 0.2 0.9)))',
                '(: (no_inverse bridge) (Implication (Y) (Z)) (CTV (STV 1 1) (STV 0 1)))',
            ])
            for repeat in range(3):
                with self.subTest(connective=connective, repeat=repeat):
                    rows = h.query_many_refs([f'(: $p (Implication {event} (Z)) $tv)'], steps=1000)[0]
                    self.assertEqual(len(rows), 1, rows)
                    self.assertAlmostEqual(rows[0].tv[1], 0.9)
                    self.assertGreater(rows[0].tv[2], 0)
                    self.assertNotIn('world', h.expand_proof(rows[0].proof))
