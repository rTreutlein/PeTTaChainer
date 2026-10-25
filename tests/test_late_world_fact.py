"""Tracker #84: late world premises refresh durable private judgments."""
import unittest

from pettachainer import PeTTaChainer


class TestLateWorldFact(unittest.TestCase):
    def test_late_world_copremise_matches_fresh(self):
        conditional = '(Implication (Implemented Split1) (Not (Dilutes Split1)))'
        existential = ('(Exists ($e) (And (Member $e StockSplit) '
                       '(Implication (Implemented $e) (Not (Dilutes $e)))))')
        base = [
            '(: src_event (Member Split1 StockSplit) (STV 1 0.9))',
            '(: src_bridge (Implication (And (Announced $e) (Implemented $e)) '
            '(Not (Dilutes $e))) (STV 1 0.9))',
        ]
        # Both a missing co-premise and a previously borrowed observation
        # must refresh; an unrelated ground query must not be required.
        for goal in (existential, conditional):
            for initial in ([], ['(: initial (Announced Split1) (STV 1 0.5))']):
                with self.subTest(goal=goal, initial=initial):
                    warm, fresh = PeTTaChainer(), PeTTaChainer()
                    warm.add_atoms_no_check(base + initial)
                    query = f'(: $p {goal} $tv)'
                    for _ in range(2):
                        before = warm.query_many_refs([query], steps=300)[0]
                        self.assertEqual(bool(before), bool(initial), before)
                    late = '(: src_split (Announced Split1) (STV 1 0.9))'
                    warm.add_atoms_no_check([late])
                    fresh.add_atoms_no_check(base + initial + [late])
                    expected = fresh.query_many_refs([query], steps=300)[0]
                    self.assertEqual(len(expected), 1, expected)
                    expected_tv = expected[0].tv
                    # An unpaid pass must retain the refresh subscription.
                    warm.query_many_refs([query], steps=0)
                    for _ in range(3):
                        actual = warm.query_many_refs([query], steps=300)[0]
                        self.assertEqual(len(actual), 1, actual)
                        self.assertEqual(actual[0].tv, expected_tv)
                        proof = warm.expand_proof(actual[0].proof)
                        for token in ('src_split', 'src_bridge', '(ctx proof '):
                            self.assertIn(token, proof)
                    self.assertEqual(warm.query_many_refs([
                        '(: $p (Implemented Split1) $tv)',
                        '(: $p (Not (Dilutes Split1)) $tv)',
                    ], steps=300), [[], []])

    def test_one_fact_refreshes_multiple_durable_judgments(self):
        for initial in ([], ['(: initial (Announced Split1) (STV 1 0.5))']):
            for late_type in ('(Announced Split1)',
                              '(And (Announced Split1) (Recorded R))'):
                with self.subTest(late_type=late_type, initial=initial):
                    warm, fresh = PeTTaChainer(), PeTTaChainer()
                    base = ['(: event (Member Split1 StockSplit) (STV 1 0.9))']
                    goals = []
                    for assumption, consequence in [('Implemented', 'Preserves'),
                                                     ('Approved', 'RecordedSplit')]:
                        base.append(f'(: bridge_{assumption} (Implication '
                                    f'(And (Announced $e) ({assumption} $e)) '
                                    f'({consequence} $e)) (STV 1 0.9))')
                        goals.append(f'(: $p (Exists ($e) (And (Member $e StockSplit) '
                                     f'(Implication ({assumption} $e) ({consequence} $e)))) $tv)')
                    warm.add_atoms_no_check(base + initial)
                    for goal in goals:
                        self.assertEqual(bool(warm.query_many_refs([goal], steps=300)[0]), bool(initial))
                    late = f'(: split {late_type} (STV 1 0.9))'
                    warm.add_atoms_no_check([late])
                    fresh.add_atoms_no_check(base + initial + [late])
                    for goal in goals:
                        expected = fresh.query_many_refs([goal], steps=300)[0]
                        self.assertEqual(len(expected), 1)
                        for _ in range(2):
                            actual = warm.query_many_refs([goal], steps=300)[0]
                            self.assertEqual([row.tv for row in actual],
                                             [row.tv for row in expected])
                            self.assertIn('split', warm.expand_proof(actual[0].proof))

if __name__ == '__main__':
    unittest.main()
