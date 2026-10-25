"""Tracker #68: negating twice preserves source evidence and independence."""
import unittest

from pettachainer import PeTTaChainer


class TestDoubleNegationEvidence(unittest.TestCase):
    def test_double_negation_query_and_premise_answer_cold(self):
        # #86: neither answered until another query compiled (Not (Q x)).
        for goal, strength in (('(Not (Not (Q x)))', 0.6), ('(W x)', 0.74),
                               ('(And (R x) (Not (Not (Q x))))', 0.3)):
            h = PeTTaChainer()
            h.add_atoms_no_check(['(: q1 (Q x) (STV 0.6 0.9))', '(: r1 (R x) (STV 0.5 0.9))',
                                  '(: rw (Implication (Not (Not (Q $v))) (W $v)) (STV 0.9 0.9))'])
            with self.subTest(goal=goal):
                rows = h.query_many_refs([f'(: $p {goal} $tv)'], steps=300)[0]
                self.assertEqual(len(rows), 1, rows)
                self.assertAlmostEqual(rows[0].tv[1], strength)
                self.assertIn('(negated (negated q1))', h.expand_proof(rows[0].proof))

    def test_double_negation_in_a_batch_reads_its_statement(self):
        # In a batch with an And over it, the double negation read the And's
        # projection: 0.6 at 0.84375, and 0.492 with a rule for Q (#86).
        for kb in (['(: q1 (Q x) (STV 0.6 0.9))'],
                   ['(: q1 (Q x) (STV 0.6 0.9))', '(: p1 (P x) (STV 0.8 0.9))',
                    '(: rq (Implication (P $v) (Q $v)) (STV 0.9 0.9))']):
            h = PeTTaChainer()
            h.add_atoms_no_check(kb)
            with self.subTest(kb=kb):
                _, double, alone = h.query_many_refs(
                    ['(: $p (And (Not (Not (Q x))) (Q x)) $tv)', '(: $p (Not (Not (Q x))) $tv)',
                     '(: $p (Q x) $tv)'], steps=300)
                self.assertEqual(len(double), 1, double)
                self.assertAlmostEqual(double[0].tv[1], alone[0].tv[1])
                self.assertAlmostEqual(double[0].tv[2], alone[0].tv[2])

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

    def test_overlapping_bridge_conditions_on_one_source(self):
        # The conditional branches have TVs (1, .8996760265350283) and
        # (0, 0). A separate CTV applied to one source is the control: it
        # counts the observation once, without the compound/judgment join.
        for confidence in (0.5, 0.9):
            control = PeTTaChainer()
            control.add_atoms_no_check([
                f'(: observation Gate (STV 1 {confidence}))',
                '(: (no_inverse control) (Implication Gate Result) (CTV (STV 1 0.8996760265350283) (STV 0 0)))',
            ])
            expected = control.query_many_refs(['(: $p Result $tv)'], steps=300)[0][0].tv
            for consequent in ('(DoesNotDilute $e)', '(Not (Dilutes $e))'):
                conjunction = f'(And (AnnouncedBy $e Apple) (AnnouncedOn $e Date20200730) (Member $e StockSplit) (Implication (Implemented $e) {consequent}))'
                for statement in (conjunction.replace('$e', 'Split1'), f'(Exists ($e) {conjunction})'):
                    h = PeTTaChainer()
                    h.add_atoms_no_check([
                        f'(: src_event (And (AnnouncedBy Split1 Apple) (AnnouncedOn Split1 Date20200730) (Member Split1 StockSplit)) (STV 1 {confidence}))',
                        f'(: src_bridge (Implication (And (Member $e StockSplit) (Implemented $e)) {consequent}) (STV 1 0.9))',
                    ])
                    for repeat in range(2):
                        with self.subTest(confidence=confidence, consequent=consequent, statement=statement, repeat=repeat):
                            rows = h.query_many_refs([f'(: $p {statement} $tv)'], steps=300)[0]
                            self.assertEqual(len(rows), 1, rows)
                            self.assertAlmostEqual(rows[0].tv[1], expected[1])
                            # Both confidences come from variances at the strength
                            # clip (~1e-9), where the two paths weigh the unknown
                            # branch's 1/12 differently by a few 1e-6.
                            self.assertAlmostEqual(rows[0].tv[2], expected[2], places=4)
                            proof = h.expand_proof(rows[0].proof)
                            self.assertIn('(conditioned src_event ', proof)
                            self.assertEqual(proof.count('src_event'), 1)
                            evidence = h._call('evidence-entries', [f'(proof-ref-evidence {rows[0].proof[1]})'])[0]
                            self.assertEqual(evidence.count('src_event'), 1)
                            self.assertEqual(evidence.count('(fact-ev '), 1)
                            self.assertIn('src_bridge)', evidence)
                            self.assertIn('(rule-ev ', evidence)


if __name__ == '__main__':
    unittest.main()
