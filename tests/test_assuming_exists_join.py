"""Tracker #76: repeated-predicate conclusions are correlated witnesses."""
import unittest

from pettachainer import PeTTaChainer


class TestAssumingExistsJoin(unittest.TestCase):
    def handler(self, conclusion, *, metadata=True, strength=1, confidence=1):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            f'(: src_rule (Implication C {conclusion}) (STV {strength} {confidence}))',
        ] + (['(: src_meta (Meta Report) (STV 1 1))'] if metadata else []))
        return h

    def answer(self, h, goal):
        rows = h.query_many_refs([f'(: $p (Assuming C {goal}) $tv)'], steps=300)[0]
        self.assertEqual(len(rows), 1, rows)
        return rows[0]

    def evidence(self, h, row):
        self.assertEqual(row.proof[0], 'assuming')
        self.assertEqual(row.proof[1][0], 'proof-ref')
        return h._call('evidence-entries', [
            f'(proof-ref-evidence {row.proof[1][1]})',
        ])[0]

    def test_join_fresh_repeat_and_after_simpler_queries(self):
        for body in ('(And (A $x) (Meta Report))', '(And (Meta Report) (A $x))'):
            for conclusion in ('(And (A Obj) (A Other))', '(A Obj)', '(And (A Obj) (B Obj))'):
                with self.subTest(body=body, conclusion=conclusion):
                    h = self.handler(conclusion)
                    goal = f'(Exists ($x) {body})'
                    first = self.answer(h, goal)
                    for _ in range(2):
                        row = self.answer(h, goal)
                        self.assertEqual(row.tv, first.tv)
                        proof = h.expand_proof(row.proof)
                        for source in ('assuming', 'src_rule', 'src_meta'):
                            self.assertIn(source, proof)
                        self.assertEqual(proof.count('src_rule'), 1, proof)
                        self.assertEqual(proof.count('src_meta'), 1, proof)
                    # The certain rule's conclusion carries c .99983 through modus
                    # ponens, a prediction: its parts move by Jeffrey to 1 - O(1e-7)
                    # (P* = (n_parts P_parts + n_rule)/(n_parts + n_rule), n_rule 4.8e6).
                    self.assertAlmostEqual(first.tv[1], 1, places=6)
                    self.assertGreater(first.tv[2], .99)
                    # Existential binders stay local; concrete witnesses do
                    # not replace the public body variable.
                    _, assumption, (_, (binder,), public_body) = first.statement
                    self.assertEqual(assumption, 'C')
                    self.assertTrue(binder.startswith('$'))
                    self.assertIn(['A', binder], public_body)
                    self.answer(h, '(Exists ($x) (A $x))')
                    self.answer(h, '(A Obj)')
                    self.assertEqual(self.answer(h, goal).tv, first.tv)
                    self.assertEqual(h.query_many_refs([
                        '(: $p C $tv)', '(: $p (A Obj) $tv)', f'(: $p {goal} $tv)',
                    ], steps=300), [[], [], []])

    def test_missing_metadata_or_wrong_report_stays_unsupported(self):
        for metadata in (False, True):
            h = self.handler('(And (A Obj) (A Other))', metadata=metadata)
            report = 'WrongReport' if metadata else 'Report'
            query = f'(: $p (Assuming C (Exists ($x) (And (A $x) (Meta {report})))) $tv)'
            for _ in range(2):
                self.assertEqual(h.query_many_refs([query], steps=300), [[]])
            if not metadata:
                h.add_atoms_no_check(['(: src_meta (Meta Report) (STV 1 1))'])
                self.answer(h, '(Exists ($x) (And (A $x) (Meta Report)))')

    def test_reference_answer_survives_collection_after_context_cleanup(self):
        import janus_swi

        h = self.handler('(And (A Obj) (A Other))', strength=.6, confidence=.8)
        row = self.answer(h, '(Exists ($x) (And (A $x) (Meta Report)))')
        proof = h.expand_proof(row.proof)
        evidence = self.evidence(h, row)
        self.assertEqual(proof.count('src_rule'), 1, proof)
        self.assertEqual(proof.count('src_meta'), 1, proof)
        self.assertEqual(evidence.count('src_rule'), 1, evidence)
        self.assertEqual(evidence.count('src_meta'), 1, evidence)
        # The overlay is already gone. The returned batch must hold both the
        # stored proof DAG and its computed evidence through collection.
        self.assertFalse(janus_swi.query_once('context_entry(_,_,_,_,_)')['truth'])
        janus_swi.query_once("'stored-refs-gc!'(_), 'stored-refs-gc!'(_)")
        self.assertEqual(h.expand_proof(row.proof), proof)
        self.assertEqual(self.evidence(h, row), evidence)
        h._call('withdraw-named-rules!', ['src_rule'])
        self.assertEqual(h._call('proof-live?', [
            f'(proof-ref {row.proof[1][1]})',
        ]), ['false'])
        # Replacing the batch releases its context-only derivations, so this
        # root does not accumulate all earlier hypothetical query histories.
        self.assertEqual(h.query_many_refs(['(: $p Missing $tv)'], steps=0), [[]])
        janus_swi.query_once("'stored-refs-gc!'(_), 'stored-refs-gc!'(_)")
        self.assertFalse(janus_swi.query_once(
            "user:'&proof'(Pid, _, _, _)", {'Pid': row.proof[1][1]},
        )['truth'])
        self.assertFalse(janus_swi.query_once("user:'&query_proofs'(_)")['truth'])

    def test_one_compound_source_counts_once(self):
        # A second projection of the same ground compound is no new trial.
        # The different-predicate control has exactly one matching witness.
        for strength, confidence in ((1, 1), (.6, .8), (1, .5)):
            for goal in ('(Exists ($x) (A $x))',
                         '(Exists ($x) (And (A $x) (Meta Report)))'):
                with self.subTest(strength=strength, confidence=confidence, goal=goal):
                    control = self.handler('(And (A Obj) (B Obj))',
                                           strength=strength, confidence=confidence)
                    expected = self.answer(control, goal).tv
                    h = self.handler('(And (A Obj) (A Other))',
                                     strength=strength, confidence=confidence)
                    for _ in range(2):
                        row = self.answer(h, goal)
                        self.assertEqual(row.tv, expected)
                        proof = h.expand_proof(row.proof)
                        self.assertEqual(proof.count('src_rule'), 1, proof)
                        evidence = self.evidence(h, row)
                        if confidence < 1:
                            self.assertEqual(evidence.count('src_rule'), 1, evidence)
                        if 'Meta' in goal:
                            self.assertEqual(evidence.count('src_meta'), 1, evidence)

    def test_shared_rule_parameter_preserves_independent_trials(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: a (Bird a) (STV 1 1))',
            '(: b (Bird b) (STV 1 1))',
            '(: flies (Implication (Bird $x) (Flies $x)) (CTV (STV 0.9 0.9) (STV 0 1)))',
        ])
        for _ in range(2):
            row = self.answer(h, '(Exists ($x) (Flies $x))')
            self.assertAlmostEqual(row.tv[1], .99)
            self.assertIn('disjunction', h.expand_proof(row.proof))

    def test_report_identity_and_date_constraints(self):
        h = PeTTaChainer()
        h.add_atoms_no_check([
            '(: src_rule (Implication (Accept Report) (And (AnnouncedIn Approval Report) (AnnouncedIn StockSplit Report))) (STV 1 1))',
            '(: src_meta (And (Reporter Report Apple) (Date Report Date20200730)) (STV 1 1))',
        ])
        body = '(And (AnnouncedIn $action Report) (Reporter Report Apple) (Date Report Date20200730))'
        query = f'(: $p (Assuming (Accept Report) (Exists ($action) {body})) $tv)'
        for _ in range(2):
            rows = h.query_many_refs([query], steps=300)[0]
            self.assertEqual(len(rows), 1, rows)
            proof = h.expand_proof(rows[0].proof)
            self.assertEqual(proof.count('src_rule'), 1, proof)
            self.assertIn('src_meta', proof)
            evidence = self.evidence(h, rows[0])
            self.assertEqual(evidence.count('src_meta'), 1, evidence)
            for bad in (query.replace('Apple)', 'SomeoneElse)'),
                        query.replace('Date20200730', 'Date20210730')):
                self.assertEqual(h.query_many_refs([bad], steps=300), [[]])


if __name__ == '__main__':
    unittest.main()
