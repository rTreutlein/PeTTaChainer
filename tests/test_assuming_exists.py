"""Issue #66: source-gated witnesses in a single hypothetical world."""
from itertools import permutations
from pathlib import Path
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer
from tests.posterior_fixture_oracle import source_oracle


SOURCES = [
    '(: src_event (Implication (AcceptSource AppleReport) (And (AnnouncedBy Split1 Apple) (AnnouncedOn Split1 Date20200730) (Member Split1 StockSplit))) (STV 1 0.9))',
    '(: src_rule (Implication (AcceptSource DefinitionReport) (Implication (Member $e StockSplit) (Not (Dilutes $e)))) (STV 1 0.9))',
]
ACCEPT = '(And (AcceptSource AppleReport) (AcceptSource DefinitionReport))'
BODY = '(And (AnnouncedBy $e Apple) (AnnouncedOn $e Date20200730) (Member $e StockSplit) (Not (Dilutes $e)))'
EXISTS = f'(Exists ($e) {BODY})'


class TestAssumingExists(unittest.TestCase):
    def test_source_gated_witness_fresh_and_warm(self):
        # Load the library before the probe changes the runtime, so the load
        # replays the snapshot every other process shares instead of
        # replacing it with one for this state.
        PeTTaChainer()
        janus.consult(str(Path(__file__).with_name('assuming_exists_probe.pl')))
        janus.query_once('assuming_exists_probe_install')
        self.addCleanup(janus.query_once, 'assuming_exists_probe_clear')
        # Each shape starts cold: the ground control must not prime Exists.
        for goal in (EXISTS, BODY.replace('$e', 'Split1')):
            h = PeTTaChainer()
            h.add_atoms_no_check(SOURCES)
            values = []
            for repeat in range(2):
                with self.subTest(goal=goal, repeat=repeat):
                    rows = h.query_many_refs([f'(: $p (Assuming {ACCEPT} {goal}) $tv)'], steps=300)[0]
                    self.assertEqual(len(rows), 1, rows)
                    row = rows[0]
                    values.append(row.tv)
                    # The accepted event is a prediction (1, .9) of the compound, so its
                    # parts move by Jeffrey from their uniform priors, the prediction
                    # (n = 800 .9/.1 = 7200) revised with the parts' own estimate
                    # (n = 152/37 = 4.1 from their exact variance, P(K) = .125):
                    # 1 - (4.1 .875/7204) .571 = .99971.
                    self.assertEqual(row.tv[0], 'STV')
                    self.assertAlmostEqual(row.tv[1], 0.9997147918855503)
                    self.assertAlmostEqual(row.tv[2], 0.8314684465816465)
                    proof = h.expand_proof(row.proof)
                    for token in ('assuming', 'src_event', 'src_rule'):
                        self.assertIn(token, proof)
                    if goal == EXISTS:
                        _, facts, (_, binders, body) = row.statement
                        self.assertEqual(facts, ['And', ['AcceptSource', 'AppleReport'], ['AcceptSource', 'DefinitionReport']])
                        witness, = binders
                        self.assertTrue(witness.startswith('$'), row)
                        concrete = ['And', ['AnnouncedBy', 'Split1', 'Apple'],
                            ['AnnouncedOn', 'Split1', 'Date20200730'], ['StockSplit', 'Split1'],
                            ['Not', ['Dilutes', 'Split1']]]
                        captured = janus.query_once('assuming_exists_probe_rows(Rows)')['Rows']
                        self.assertIn([concrete, row.tv], captured)
                        self.assertEqual(body, ['And', ['AnnouncedBy', witness, 'Apple'],
                            ['AnnouncedOn', witness, 'Date20200730'], ['Member', witness, 'StockSplit'],
                            ['Not', ['Dilutes', witness]]])
            self.assertEqual(len(values), 2)
            self.assertEqual(values, values[:1] * 2)
            self.assertEqual(h.query_many_refs([
                f'(: $p {term} $tv)' for term in (
                    '(AcceptSource AppleReport)', '(AcceptSource DefinitionReport)',
                    '(AnnouncedBy Split1 Apple)', '(AnnouncedOn Split1 Date20200730)',
                    '(Member Split1 StockSplit)', '(Not (Dilutes Split1))', EXISTS,
                )], steps=300), [[]] * 7)
            self.assertFalse(janus.query_once('context_entry(_,_,_,_,_)')['truth'])
            self.assertFalse(janus.query_once('context_seed(_,_,_)')['truth'])

    def test_matched_primary_controls(self):
        cases = [
            ('missing_event', SOURCES[1:], ACCEPT, EXISTS),
            ('missing_rule', SOURCES[:1], ACCEPT, EXISTS),
            ('no_acceptance', SOURCES, None, EXISTS),
            ('missing_event_acceptance', SOURCES, '(AcceptSource DefinitionReport)', EXISTS),
            ('missing_rule_acceptance', SOURCES, '(AcceptSource AppleReport)', EXISTS),
            ('wrong_date', SOURCES, ACCEPT, EXISTS.replace('Date20200730', 'Date20210730')),
        ]
        for name, sources, facts, goal in cases:
            h = PeTTaChainer()
            h.add_atoms_no_check(sources)
            expression = f'(Assuming {facts} {goal})' if facts else goal
            for repeat in range(2):
                with self.subTest(case=name, repeat=repeat):
                    self.assertEqual(h.query_many_refs([f'(: $p {expression} $tv)'], steps=300), [[]])

    def test_pooling_respects_negated_premise_in_each_position(self):
        for terms in permutations(('(P x)', '(Q x)', '(Not (R x))')):
            h = PeTTaChainer()
            h.add_atoms_no_check([
                '(: bundle (And (P x) (Q x)) (STV 0.9 0.8))',
                '(: r (R x) (STV 0.3 0.9))',
            ])
            expression = '(And ' + ' '.join(terms) + ')'
            for repeat in range(2):
                with self.subTest(terms=terms, repeat=repeat):
                    rows = h.query_many_refs([f'(: $p {expression} $tv)'], steps=300)[0]
                    self.assertEqual(len(rows), 1, rows)
                    # The bundle is one Pearl factor on the joint P/Q event;
                    # the independent R parameter is complemented once.
                    expected = source_oracle([
                        '(: bundle (And (P x) (Q x)) (STV 0.9 0.8))',
                        '(: r (R x) (STV 0.3 0.9))'], expression, ratio_bound=True)
                    self.assertAlmostEqual(rows[0].tv[1], expected['s'], delta=1e-12)
                    self.assertAlmostEqual(rows[0].tv[2], expected['bound_c'], delta=1e-7)

    def test_pooling_source_names_are_scoped_to_their_kb(self):
        other = PeTTaChainer()
        other.add_atoms_no_check(['(: reused (Other x) (STV 1 1))'])
        h = PeTTaChainer()
        h.add_atoms_no_check(['(: reused (And (P x) (Q x)) (STV 0.9 0.8))'])
        for repeat in range(2):
            with self.subTest(repeat=repeat):
                rows = h.query_many_refs(['(: $p (And (Q x) (P x)) $tv)'], steps=300)[0]
                self.assertEqual(len(rows), 1, rows)
                expected = source_oracle(['(: reused (And (P x) (Q x)) (STV 0.9 0.8))'], '(And (Q x) (P x))', ratio_bound=True)
                self.assertAlmostEqual(rows[0].tv[1], expected['s'], delta=1e-12)
                self.assertAlmostEqual(rows[0].tv[2], expected['bound_c'], delta=1e-7)

    def test_unrelated_world_support_answers_assuming(self):
        h = PeTTaChainer()
        h.add_atoms_no_check(['(: world (Recorded Split1) (STV 0.7 0.8))'])
        for repeat in range(2):
            with self.subTest(repeat=repeat):
                rows = h.query_many_refs([
                    '(: $p (Assuming (Implemented Split1) (Exists ($e) (Recorded $e))) $tv)',
                ], steps=300)[0]
                self.assertEqual(len(rows), 1, rows)
                self.assertEqual(rows[0].tv, ['STV', 0.7, 0.8])
                self.assertIn('world', h.expand_proof(rows[0].proof))
        self.assertEqual(h.query_many_refs(['(: $p (Implemented Split1) $tv)'], steps=300), [[]])


if __name__ == '__main__':
    unittest.main()
