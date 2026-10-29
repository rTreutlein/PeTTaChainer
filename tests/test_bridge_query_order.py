"""Tracker #73: temporary judgments must not exhaust later witness searches."""
import unittest

from pettachainer import PeTTaChainer


class TestBridgeQueryOrder(unittest.TestCase):
    def test_bridge_queries_match_single_expression_in_both_orders(self):
        identity = '(And (AnnouncedBy Split1 Apple) (AnnouncedOn Split1 Date20200730) (Member Split1 StockSplit))'
        for consequent in ('(DoesNotDilute $e)', '(Not (Dilutes $e))'):
            body = f'(And (AnnouncedBy $e Apple) (AnnouncedOn $e Date20200730) (Member $e StockSplit) (Implication (Implemented $e) {consequent}))'
            expressions = (body.replace('$e', 'Split1'), f'(Exists ($e) {body})')
            for confidence in (0.5, 0.9, 1.0):
                atoms = [
                    f'(: src_event {identity} (STV 1 {confidence}))',
                    f'(: src_bridge (Implication (And (Member $e StockSplit) (Implemented $e)) {consequent}) (STV 1 0.9))',
                ]
                expected = []
                # A repeated single expression is the independent reference.
                for expression in expressions:
                    h = PeTTaChainer()
                    h.add_atoms_no_check(atoms)
                    for repeat in range(2):
                        with self.subTest(reference=expression, confidence=confidence, repeat=repeat):
                            rows = h.query_many_refs([f'(: $p {expression} $tv)'], steps=300)[0]
                            self.assertEqual(len(rows), 1, rows)
                            if repeat == 0:
                                expected.append(rows[0].tv)
                            else:
                                self.assertEqual(rows[0].tv, expected[-1])
                self.assertEqual(expected[0], expected[1])
                if confidence == 0.9:
                    # The identity is an observation read at its Pearl factor (exact
                    # only at confidence 1), its parts read conditioned on it with
                    # the bridge's conditional.
                    self.assertAlmostEqual(expected[0][2], 0.8177148713822444)
                for first, second in ((0, 1), (1, 0)):
                    h = PeTTaChainer()
                    h.add_atoms_no_check(atoms)
                    # Warm each shape, then switch repeatedly. A single switch
                    # misses losing a temporary producer after a later query.
                    for turn, index in enumerate((first, first, second, second, first, second, first, second)):
                        with self.subTest(consequent=consequent, confidence=confidence,
                                          order=(first, second), turn=turn):
                            rows = h.query_many_refs([f'(: $p {expressions[index]} $tv)'], steps=300)[0]
                            self.assertEqual(len(rows), 1, rows)
                            self.assertEqual(rows[0].tv, expected[index])
                            proof = h.expand_proof(rows[0].proof)
                            self.assertIn('src_bridge', proof)
                            self.assertIn('(ctx proof ', proof)
                            if confidence < 1:
                                self.assertEqual(proof.count('src_event'), 1, proof)
                                evidence = h._call('evidence-entries', [
                                    f'(proof-ref-evidence {rows[0].proof[1]})',
                                ])[0]
                                self.assertEqual(evidence.count('src_event'), 1, evidence)
                            if index == 1:
                                self.assertEqual(rows[0].statement[0], 'Exists')
                                witness = rows[0].statement[1][0]
                                self.assertNotEqual(witness, 'Split1')
                                self.assertEqual(rows[0].statement[2][1], ['AnnouncedBy', witness, 'Apple'])
                    self.assertEqual(h.query_many_refs([
                        '(: $p (Implemented Split1) $tv)',
                        f'(: $p {consequent.replace("$e", "Split1")} $tv)',
                    ], steps=300), [[], []])

    def test_preexpanded_judgment_tracks_a_late_world_source(self):
        h = PeTTaChainer()
        event = '(: src_event (And (Member Split1 StockSplit) (Recorded Split1)) (STV 1 0.9))'
        bridge = '(: src_bridge (Implication (And (Member $e StockSplit) (Implemented $e)) (DoesNotDilute $e)) (STV 1 0.9))'
        h.add_atoms_no_check([bridge])
        conditional = '(Implication (Implemented Split1) (DoesNotDilute Split1))'
        body = '(And (Member $e StockSplit) (Recorded $e) (Implication (Implemented $e) (DoesNotDilute $e)))'
        queries = [f'(: $p {body.replace("$e", "Split1")} $tv)',
                   f'(: $p (Exists ($e) {body}) $tv)']
        # The shared node can also have been expanded as a root, which does
        # not call implicit subgoal compilation during its first expansion.
        self.assertEqual(h.query_many_refs([f'(: $p {conditional} $tv)'], steps=300)[0], [])
        h.add_atoms_no_check([event])
        expected = None
        for query in queries * 4:
            rows = h.query_many_refs([query], steps=300)[0]
            self.assertEqual(len(rows), 1, rows)
            if expected is None:
                expected = rows[0].tv
            self.assertEqual(rows[0].tv, expected)
        self.assertEqual(h.query_many_refs([
            '(: $p (Implemented Split1) $tv)',
            '(: $p (DoesNotDilute Split1) $tv)',
        ], steps=300), [[], []])


if __name__ == '__main__':
    unittest.main()
