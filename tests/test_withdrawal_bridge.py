"""Tracker #75: cached judgments retain rule provenance under conditioning."""
import unittest

from pettachainer import PeTTaChainer


class TestWithdrawalBridge(unittest.TestCase):
    def test_withdrawn_bridge_cannot_supply_an_existential_witness(self):
        for confidence in (0.9, 0.5, 1.0):
            with self.subTest(confidence=confidence):
                h = PeTTaChainer()
                h.add_atoms_no_check([
                    f'(: src_event (And (AnnouncedBy Split1 Apple) (AnnouncedOn Split1 Date20200730) (Member Split1 StockSplit)) (STV 1 {confidence}))',
                    '(: src_bridge (Implication (And (Member $e StockSplit) (Implemented $e)) (DoesNotDilute $e)) (STV 1 0.9))',
                ])
                body = '(And (AnnouncedBy $e Apple) (AnnouncedOn $e Date20200730) (Member $e StockSplit) (Implication (Implemented $e) (DoesNotDilute $e)))'
                queries = [f'(: $p (Exists ($e) {body}) $tv)',
                           f'(: $p {body.replace("$e", "Split1")} $tv)']
                for query in queries:
                    rows = h.query_many_refs([query], steps=300)[0]
                    self.assertEqual(len(rows), 1, rows)
                    self.assertIn('src_bridge', h.expand_proof(rows[0].proof))
                h._call('withdraw-named-rules!', ['src_bridge'])
                # Warm cached witnesses and grounded judgments must both go.
                for query in queries:
                    self.assertEqual(h.query_many_refs([query], steps=300)[0], [])

    def test_conditioned_witness_and_aggregate_drop_retired_members(self):
        expressions = [
            '(Exists ($x) (And (A $x) (B $x)))',
            '(FoldAll (And (A $x) (B $x)) 1 0 (|-> ($acc $elem) (+ $acc $elem)) -> $total)',
            '(FoldAllTruth (And (A $x) (B $x)) (STV $s $_c) $s 0 (|-> ($acc $elem) (+ $acc $elem)) -> $total)',
        ]
        for expression in expressions:
            with self.subTest(expression=expression):
                h = PeTTaChainer()
                h.add_atoms_no_check([
                    '(: a (A a) (STV 1 0.9))',
                    # Certain rule parameters supply no statistical evidence.
                    '(: retired (Implication (A $x) (B $x)) (CTV (STV 0.8 1) (STV 0 1)))',
                ])
                query = f'(: $p {expression} $tv)'
                before = h.query_many_refs([query], steps=100)[0]
                self.assertEqual(len(before), 1, before)
                self.assertIn('conditioned', h.expand_proof(before[0].proof))
                h._call('withdraw-named-rules!', ['retired'])
                proof = f'(proof-ref {before[0].proof[1]})'
                # Check the immutable answer itself, before any new evaluation.
                self.assertEqual(h._call('proof-live?', [proof]), ['false'])
                for _ in range(2):
                    after = h.query_many_refs([query], steps=100)[0]
                    if expression.startswith('(Exists'):
                        self.assertEqual(after, [])
                    else:
                        self.assertEqual(len(after), 1, after)
                        self.assertEqual(after[0].statement[-1], 0)
                        self.assertNotIn('retired', h.expand_proof(after[0].proof))

    def test_conditioned_answer_keeps_live_alternative_and_new_rule_identity(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: a (A a) (STV 1 0.9))',
            '(: old (Implication (A $x) (B $x)) (CTV (STV 0.8 1) (STV 0 1)))',
            '(: live (Implication (A $x) (B $x)) (CTV (STV 0.2 1) (STV 0 1)))',
        ])
        query = '(: $p (Exists ($x) (And (A $x) (B $x))) $tv)'
        before = h.query_many_refs([query], steps=100)[0]
        self.assertEqual(len(before), 1, before)
        h._call('withdraw-named-rules!', ['old'])
        for _ in range(2):
            rows = h.query_many_refs([query], steps=100)[0]
            self.assertEqual(len(rows), 1, rows)
            self.assertAlmostEqual(rows[0].tv[1], 0.2)
            proof = h.expand_proof(rows[0].proof)
            self.assertIn('live', proof)
            self.assertNotIn('old', proof)
        h._call('withdraw-named-rules!', ['live'])
        self.assertEqual(h.query_many_refs([query], steps=100)[0], [])
        # The withdrawn name keeps its value (#113): the new rule takes a new name.
        h.add_atom('(: renewed (Implication (A $x) (B $x)) (CTV (STV 0.6 1) (STV 0 1)))')
        for _ in range(2):
            rows = h.query_many_refs([query], steps=100)[0]
            self.assertEqual(len(rows), 1, rows)
            self.assertAlmostEqual(rows[0].tv[1], 0.6)


if __name__ == '__main__':
    unittest.main()
