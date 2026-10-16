"""Tracker #68: negating twice preserves source evidence and independence."""
import unittest

from pettachainer import PeTTaChainer


class TestDoubleNegationEvidence(unittest.TestCase):
    def test_explicit_conditional_matches_positive_control(self):
        confidences = []
        for consequent in ('(DoesNotDilute $e)', '(Not (Dilutes $e))'):
            h = PeTTaChainer()
            h.add_atoms_no_check([
                '(: src_event (And (AnnouncedBy Split1 Apple) (AnnouncedOn Split1 Date20200730) (Member Split1 StockSplit)) (STV 1 0.9))',
                f'(: src_conditional (Implication (Implemented Split1) {consequent.replace("$e", "Split1")}) (STV 1 0.9))',
            ])
            query = f'(: $p (Exists ($e) (And (AnnouncedBy $e Apple) (AnnouncedOn $e Date20200730) (Member $e StockSplit) (Implication (Implemented $e) {consequent}))) $tv)'
            for repeat in range(2):
                with self.subTest(consequent=consequent, repeat=repeat):
                    rows = h.query_many_refs([query], steps=300)[0]
                    self.assertEqual(len(rows), 1, rows)
                    self.assertAlmostEqual(rows[0].tv[1], 1.0)
                    self.assertAlmostEqual(rows[0].tv[2], 0.8181611546663349)
                    confidences.append(rows[0].tv[2])
        self.assertTrue(all(abs(value - confidences[0]) < 1e-12 for value in confidences))

    def test_overlapping_bridge_matches_positive_control(self):
        # Restoring src_event exposes the same overlap as the positive form.
        # Conditioning this compound/judgment join is a separate limitation.
        for consequent in ('(DoesNotDilute $e)', '(Not (Dilutes $e))'):
            h = PeTTaChainer()
            h.add_atoms_no_check([
                '(: src_event (And (AnnouncedBy Split1 Apple) (AnnouncedOn Split1 Date20200730) (Member Split1 StockSplit)) (STV 1 0.9))',
                f'(: src_bridge (Implication (And (Member $e StockSplit) (Implemented $e)) {consequent}) (STV 1 0.9))',
            ])
            conjunction = f'(And (AnnouncedBy $e Apple) (AnnouncedOn $e Date20200730) (Member $e StockSplit) (Implication (Implemented $e) {consequent}))'
            for statement in (conjunction.replace('$e', 'Split1'), f'(Exists ($e) {conjunction})'):
                for repeat in range(2):
                    with self.subTest(consequent=consequent, statement=statement, repeat=repeat):
                        self.assertEqual(h.query_many_refs([f'(: $p {statement} $tv)'], steps=300), [[]])


if __name__ == '__main__':
    unittest.main()
