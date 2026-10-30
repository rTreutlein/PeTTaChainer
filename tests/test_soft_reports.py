"""Reports update independent predictions by their likelihood, after corroboration (B2, Pearl)."""
import unittest

import janus_swi as janus
from pettachainer import PeTTaChainer
from tests.tv_calibration_oracles import predictive, event_oracle, variance_ratio


def posterior(prior, strength, confidence, k=5):
    """Pearl update with the independent oracle's predictive likelihood."""
    m = predictive(strength, confidence, k)
    return prior * m / (prior * m + (1 - prior) * (1 - m))


class SoftReportTests(unittest.TestCase):
    def test_finite_endpoint_reports_match_the_event_oracle(self):
        # A finite endpoint branch is a Beta parameter, not a hard event.
        # Check the small event to retain the oracle's tiny variance digits.
        for strength in (0, 1):
            with self.subTest(strength=strength):
                h = PeTTaChainer()
                h.add_atoms_no_check([
                    '(: cause (C a) (STV 1 1))',
                    f'(: cp (Implication (C a) (P a)) (CTV (STV {strength} 0.8) (STV {1-strength} 1)))',
                ])
                model = dict(atoms=['C', 'P'], roots={'C': (1, 1)},
                             rules={'P': ('C', (strength, .8), (1-strength, 1))},
                             comps=[], goals={'small': lambda w: ~w['P'] if strength else w['P']})
                for reports in (1, 2):
                    confidence = .8 if reports == 1 else .5
                    h.add_atoms_no_check([f'(: report{reports} (P a) (STV {strength} {confidence}))'])
                    model['comps'].append(('P', lambda w: w['P'], strength, confidence))
                    expected = event_oracle(model)['small']
                    answer, = h.query_many_refs(['(: $p (P a) $tv)'], steps=3000)[0]
                    small = 1 - answer.tv[1] if strength else answer.tv[1]
                    self.assertAlmostEqual(small, expected['s'], delta=1e-12)
                    self.assertTrue(.5 <= variance_ratio(small, answer.tv[2], expected) <= 2)

    def test_endpoint_update_keeps_prediction_evidence_and_dependencies(self):
        for strength in (0, 1):
            with self.subTest(strength=strength):
                h = PeTTaChainer()
                h.add_atoms_no_check([
                    '(: cause (C a) (STV 1 0.8))',
                    f'(: cp (Implication (C a) (P a)) (CTV (STV {strength} 1) (STV {strength} 1)))',
                ])
                query = ['(: $p (P a) $tv)']
                h.query_many_refs(query, steps=3000)
                before = janus.query_once(
                    "'sk-value'(['sk-key',['P',a],[Kb,'MAIN','Nil']], 'sk-any-filter', [], "
                    "['sk-val',_,Ev,Deps])", {'Kb': h.kb})
                h.add_atoms_no_check([f'(: report (P a) (STV {strength} 0.8))'])
                answer = h.query_many_refs(query, steps=3000)[0][0]
                after = janus.query_once(
                    "'sk-value'(['sk-key',['P',a],[Kb,'MAIN','Nil']], 'sk-any-filter', [], "
                    "['sk-val',_,Ev,Deps]), 'evidence-subset?'(BeforeEv,Ev,EvidenceKept), "
                    "'deps-within?'(BeforeDeps,Deps,DependenciesKept), 'evidence-entries'(Ev,Entries)",
                    {'Kb': h.kb, 'BeforeEv': before['Ev'], 'BeforeDeps': before['Deps']})
                self.assertEqual(after['EvidenceKept'], 'true')
                self.assertEqual(after['DependenciesKept'], 'true')
                for source, statement in (('cause', ['C', 'a']), ('report', ['P', 'a'])):
                    self.assertIn(['fact-ev', [h.kb, 'MAIN', 'Nil'], source, statement], after['Entries'])
                proof = h.expand_proof(answer.proof)
                self.assertIn('cause', proof)
                self.assertIn('(by cp cpu)', proof)

    def test_stored_cut_excludes_a_prediction_sharing_branch_evidence(self):
        h = PeTTaChainer()
        h.set_bayes_prior_count(0)
        self.addCleanup(h.set_bayes_prior_count, .2)
        h.add_atoms_no_check([
            '(: report (P a) (STV 0.6 0.5))',
            '(: forecast (F a) (STV 0.9 0.9))',
            '(: fp (Implication (F a) (P a)) (CTV (STV 0.9 1) (STV 0.1 1)))',
            '(: pa (Implication (P a) (A a)) (CTV (STV 0.8 1) (STV 0.1 1)))',
            '(: root (Implication (And (A a) (F a)) (T a)) (CTV (STV 1 1) (STV 0 1)))',
        ])
        rows = h.query_many_refs(['(: $p (P a) $tv)', '(: $p (T a) $tv)'], steps=20000)
        self.assertNotAlmostEqual(rows[0][0].tv[1], .6)
        result = janus.query_once(
            "Scope=[Kb,'MAIN','Nil'], Pin=['sk-key',['P',a],Scope], "
            "Key=['sk-key',['T',a],Scope], 'index-hash'(Pin,PH), 'index-hash'(Key,H), "
            "Target=['sk-key-target',H,Key,'sk-any-filter',[]], "
            "'change-state!'(sk_eval_budget,20000,_), 'change-state!'(sk_claim_depth,64,_), "
            "setup_call_cleanup('sk-open-claim!'(_), ("
            "'sk-target-value'([['sk-given',PH,Pin,true]],Target,['sk-val',[_,_,_,['STV',Yes,_]],YE,_]), "
            "'sk-target-value'([['sk-given',PH,Pin,false]],Target,['sk-val',[_,_,_,['STV',No,_]],NE,_]), "
            "'evidence-union'(YE,NE,Branch), 'evidence-negated'(Branch,Negative), "
            "'evidence-union'(Branch,Negative,Both), "
            "'sk-compatible-value'([],Pin,'sk-any-filter',[],Both,true, "
            " ['sk-val',[_,_,_,['STV',Weight,_]],_,_]), "
            "'sk-mix-on'([],Target,[],[Pin],[['sk-val',[_,_,_,['STV',Mixed,_]],_,_]])), "
            "'sk-close-claim!'(_))", {'Kb': h.kb})
        self.assertTrue(result['truth'])
        self.assertAlmostEqual(result['Weight'], .6, delta=1e-12)
        self.assertNotAlmostEqual(result['Yes'], result['No'])
        self.assertAlmostEqual(result['Mixed'], .6 * result['Yes'] + .4 * result['No'], delta=1e-12)

    def model(self, confidence, strength=1):
        h = PeTTaChainer()
        h.set_evidence_confidence_k(5)
        self.addCleanup(h.set_evidence_confidence_k, 800)
        h.add_atoms_no_check([
            '(: w (W a) (STV 1 1))',
            '(: wz (Implication (W a) (Z a)) (CTV (STV 0.5 1) (STV 0.5 1)))',
            '(: zp (Implication (Z a) (P a)) (CTV (STV 0.9 1) (STV 0.1 1)))',
            f'(: report (P a) (STV {strength} {confidence}))',
            '(: pq (Implication (P a) (Q a)) (CTV (STV 0.8 1) (STV 0.3 1)))',
        ])
        return h

    def test_direct_consequence_and_inversion_agree_with_forward(self):
        queries = [f'(: $p ({name} a) $tv)' for name in ('P', 'Q', 'Z')]
        for c in (.5, .9, .99, 1):
            for strength in (0, .3, 1):
                answers = []
                for forward in (False, True):
                    with self.subTest(confidence=c, strength=strength, forward=forward):
                        h = self.model(c, strength)
                        if forward:
                            h.forward_chain(h.select_facts(['(W a)', '(P a)']), steps=3000)
                        rows = h.query_many_refs(queries, steps=3000)
                        self.assertEqual([len(row) for row in rows], [1, 1, 1])
                        values = [row[0].tv[1] for row in rows]
                        expected = predictive(strength, c, 5)
                        self.assertAlmostEqual(values[0], expected, delta=1e-12)
                        self.assertGreater(rows[0][0].tv[2], 0)
                        self.assertAlmostEqual(values[1], .3 + .5 * expected, delta=1e-12)
                        self.assertAlmostEqual(values[2], .1 + .8 * expected, delta=1e-12)
                        if c < 1:
                            self.assertIn('report', h.expand_proof(rows[0][0].proof))
                        answers.append(values)
                if len(answers) == 2:
                    for backward, forward in zip(*answers):
                        self.assertAlmostEqual(backward, forward, delta=1e-12)

    def test_late_observation_updates_a_warm_prediction(self):
        for forward in (False, True):
            with self.subTest(forward=forward):
                h = self.model(0)
                if forward:
                    h.forward_chain(h.select_facts('(W a)'), steps=3000)
                query = ['(: $p (P a) $tv)', '(: $p (Q a) $tv)']
                self.assertAlmostEqual(h.query_many_refs(query, steps=3000)[0][0].tv[1], .5)
                h.add_atoms_no_check(['(: late-report (P a) (STV 1 0.9))'])
                rows = h.query_many_refs(query, steps=3000)
                self.assertAlmostEqual(rows[0][0].tv[1], predictive(1, .9, 5))
                self.assertAlmostEqual(rows[1][0].tv[1], .3 + .5 * predictive(1, .9, 5))

    def test_late_observation_updates_a_frozen_prediction(self):
        h = self.model(0)
        h.set_forgetting(1)
        self.addCleanup(h.set_forgetting, 0)
        query = ['(: $p (P a) $tv)']
        self.assertAlmostEqual(h.query_many_refs(query, steps=3000)[0][0].tv[1], .5)
        h.advance_epoch()
        h.advance_epoch()
        frozen = h.query_many_refs(query, steps=3000)[0][0]
        self.assertIn('forgotten', h.expand_proof(frozen.proof))
        h.add_atoms_no_check(['(: late-report (P a) (STV 1 0.9))'])
        rows = h.query_many_refs(query + ['(: $p (Q a) $tv)'], steps=3000)
        self.assertEqual(rows[0][0].tv[1], 1)
        self.assertAlmostEqual(rows[1][0].tv[1], .8)
        self.assertIn('forgotten', h.expand_proof(rows[0][0].proof))

    def test_filtered_observation_does_not_hide_prediction(self):
        h = self.model(.9)
        # Surface validation accepts only proof names; exercise the runtime's
        # existing constrained-proof query directly.
        rows = h._call('query', [f'3000 {h.kb} (: (by zp $body) (P a) $tv)'])
        self.assertEqual(len(rows), 1)
        self.assertIn('(STV 0.5 ', rows[0])

    def test_negative_report_has_the_same_value(self):
        h = self.model(0)
        h.add_atoms_no_check(['(: negative-report (Not (P a)) (STV 1 0.9))'])
        rows = h.query_many_refs(['(: $p (P a) $tv)', '(: $p (Q a) $tv)'], steps=3000)
        self.assertAlmostEqual(rows[0][0].tv[1], predictive(0, .9, 5))
        self.assertAlmostEqual(rows[1][0].tv[1], .3 + .5 * predictive(0, .9, 5))

    def test_independent_reports_multiply_their_predictive_likelihoods(self):
        h = self.model(.9)
        h.add_atoms_no_check(['(: other-report (P a) (STV 0 0.5))'])
        rows = h.query_many_refs(['(: $p (P a) $tv)'], steps=3000)[0]
        self.assertEqual(len(rows), 1)
        m1, m0 = predictive(1, .9, 5), predictive(0, .5, 5)
        self.assertAlmostEqual(rows[0].tv[1], m1*m0/(m1*m0+(1-m1)*(1-m0)), delta=1e-12)
        self.assertEqual(rows[0].tv[2], .9999)

    def test_fractional_reports_update_the_prediction_as_prior(self):
        for c in (.5, .9, .99, 1):
            for prediction, report in ((.1, .6), (0, .8), (.99, .6)):
                answers = []
                for forward in (False, True):
                    with self.subTest(c=c, prediction=prediction, report=report, forward=forward):
                        h = PeTTaChainer()
                        h.set_evidence_confidence_k(5)
                        self.addCleanup(h.set_evidence_confidence_k, 800)
                        h.add_atoms_no_check([
                            '(: cause (C a) (STV 1 1))',
                            f'(: cp (Implication (C a) (P a)) (CTV (STV {prediction} 1) (STV {prediction} 1)))',
                            f'(: report (P a) (STV {report} {c}))',
                            '(: pq (Implication (P a) (Q a)) (CTV (STV 0.8 1) (STV 0.3 1)))',
                        ])
                        if forward:
                            h.forward_chain(h.select_facts(['(C a)', '(P a)']), steps=3000)
                        rows = h.query_many_refs(['(: $p (P a) $tv)', '(: $p (Q a) $tv)'], steps=3000)
                        self.assertEqual([len(row) for row in rows], [1, 1])
                        expected = posterior(prediction, report, c)
                        self.assertAlmostEqual(rows[0][0].tv[1], expected, delta=1e-12)
                        self.assertAlmostEqual(rows[1][0].tv[1], .3 + .5 * expected, delta=1e-12)
                        self.assertEqual(rows[0][0].tv[2], .9999)
                        answers.append(rows[0][0].tv[1])
                self.assertAlmostEqual(*answers, delta=1e-12)

    def test_report_updates_a_prediction_with_independent_diagnostics(self):
        for c in (.5, .9, .99):
            h = PeTTaChainer()
            h.set_bayes_prior_count(0)
            self.addCleanup(h.set_bayes_prior_count, .2)
            h.add_atoms_no_check([
                '(: cause (C a) (STV 1 1))',
                '(: cp (Implication (C a) (P a)) (CTV (STV 0.1 1) (STV 0.1 1)))',
                '(: pq (Implication (P a) (Q a)) (CTV (STV 0.8 1) (STV 0.2 1)))',
                '(: sensor (Q a) (STV 1 1))',
                f'(: report (P a) (STV 0.6 {c}))',
            ])
            row = h.query_many_refs(['(: $p (P a) $tv)'], steps=3000)[0][0]
            # Prior odds 1/9, report likelihood ratio 3/2, sensor ratio 4.
            self.assertAlmostEqual(row.tv[1], posterior(4/13, .6, c, 800), delta=1e-12)
            proof = h.expand_proof(row.proof)
            for source in ('cause', 'sensor', 'report'):
                self.assertIn(source, proof)

    def test_distinct_reports_are_distinct_likelihood_factors(self):
        for forward in (False, True):
            h = PeTTaChainer()
            h.set_evidence_confidence_k(5)
            self.addCleanup(h.set_evidence_confidence_k, 800)
            h.add_atoms_no_check([
                '(: cause (C a) (STV 1 1))',
                '(: cp (Implication (C a) (P a)) (CTV (STV 0.5 1) (STV 0.5 1)))',
                '(: r1 (P a) (STV 0.6 0.5))',
                '(: r2 (P a) (STV 0.6 0.5))',
            ])
            if forward:
                h.forward_chain(h.select_facts(['(C a)', '(P a)']), steps=3000)
            row = h.query_many_refs(['(: $p (P a) $tv)'], steps=3000)[0][0]
            m = predictive(.6, .5, 5)
            self.assertAlmostEqual(row.tv[1], m*m/(m*m+(1-m)**2), delta=1e-12)
            self.assertEqual(row.tv[2], .9999)
            proof = h.expand_proof(row.proof)
            self.assertIn('r1', proof)
            self.assertIn('r2', proof)

    def test_population_and_explicit_rate_leave_a_report_unchanged(self):
        # A report is a likelihood, not a posterior formed under the
        # population's rate: later members and a stated rate do not move it.
        h = PeTTaChainer()
        h.set_evidence_confidence_k(5)
        self.addCleanup(h.set_evidence_confidence_k, 800)
        h.add_atoms_no_check([
            '(: cause (C a) (STV 1 1))',
            '(: cp (Implication (C $x) (P $x)) (CTV (STV 0.1 1) (STV 0.1 1)))',
            '(: report (P a) (STV 0.6 0.9))',
            '(: pq (Implication (P a) (Q a)) (CTV (STV 0.8 1) (STV 0.3 1)))',
        ])
        q = ['(: $p (Q a) $tv)', '(: $p (P a) $tv)']
        for change in ([], ['(: pb (P b) (STV 0.2 1))', '(: pc (P c) (STV 0.2 1))'], 'rate'):
            if change == 'rate':
                h._call('set-base-rate', [f'{h.kb} (P $x) (STV 0.8 1)'])
            else:
                h.add_atoms_no_check(change)
            rows = h.query_many_refs(q, steps=3000)
            expected = posterior(.1, .6, .9)
            self.assertAlmostEqual(rows[1][0].tv[1], expected, delta=1e-12)
            self.assertAlmostEqual(rows[0][0].tv[1], .3 + .5 * expected, delta=1e-12)

    def test_certain_population_member_does_not_calibrate_a_report(self):
        # B is derived from A and also reported; (B y) is a certain false
        # member of B's population. A report reads as its likelihood, so the
        # member changes nothing (calibrating against its rate of 0 made any
        # report read as near certain).
        for diamond in (False, True):
            for strength, confidence in ((.1, .9), (.5, 1)):
                with self.subTest(diamond=diamond, strength=strength, confidence=confidence):
                    h = PeTTaChainer()
                    h.add_atoms_no_check([
                        '(: fa (A x) (STV 0.3 1))',
                        '(: r1 (Implication (A $x) (B $x)) (CTV (STV 0.9 1) (STV 0.2 1)))',
                        '(: r2 (Implication (B $x) (C $x)) (CTV (STV 0.8 1) (STV 0.1 1)))',
                        f'(: fb (B x) (STV {strength} {confidence}))',
                        '(: fa-y (A y) (STV 0.3 1))',
                        '(: fb-y (B y) (STV 0 1))',
                    ] + ([
                        '(: r3 (Implication (B $x) (D $x)) (CTV (STV 0.7 1) (STV 0.2 1)))',
                        '(: r4 (Implication (And (C $x) (D $x)) (E $x)) (CTV (STV 0.9 1) (STV 0.05 1)))',
                    ] if diamond else []))
                    root = h.query_many_refs([f'(: $p ({"E" if diamond else "C"} x) $tv)'], steps=20000)[0][0]
                    # P(root | B) and P(root | not B); in the diamond C and D are independent given B.
                    true, false = (.56 * .9 + .44 * .05, .02 * .9 + .98 * .05) if diamond else (.8, .1)
                    downstream = lambda b: b * true + (1 - b) * false
                    expected = downstream(posterior(.3*.9 + .7*.2, strength, confidence, 800))
                    self.assertAlmostEqual(root.tv[1], expected, delta=1e-12)

    def test_frozen_diagnostic_summary_remains_the_prior(self):
        h = PeTTaChainer()
        h.set_evidence_confidence_k(5)
        self.addCleanup(h.set_evidence_confidence_k, 800)
        h.set_forgetting(1)
        self.addCleanup(h.set_forgetting, 0)
        h.add_atoms_no_check([
            '(: q (Q a) (STV 1 1))',
            '(: pq (Implication (P a) (Q a)) (CTV (STV 0.8 1) (STV 0.2 1)))',
        ])
        query = ['(: $p (P a) $tv)']
        prior = h.query_many_refs(query, steps=3000)[0][0].tv[1]
        # Statistical fold members normally replay on expiry. Freeze the
        # actual diagnostic row through the summary writer to exercise a
        # retained historical diagnostic, without replacing it by a fixture.
        key = f'(sk-key (P a) ({h.kb} MAIN Nil))'
        key_hash = int(h._call('index-hash', [key])[0])
        h._call('sk-freeze!', [f'1 () ({key_hash} {key} false)'])
        frozen = h.query_many_refs(query, steps=3000)[0][0]
        self.assertIn('forgotten', h.expand_proof(frozen.proof))
        h.add_atoms_no_check(['(: report (P a) (STV 0.6 0.9))'])
        posterior = h.query_many_refs(query, steps=3000)[0][0]
        expected = prior * .6 / (prior * .6 + (1 - prior) * .4)
        self.assertAlmostEqual(posterior.tv[1], expected)
        proof = h.expand_proof(posterior.proof)
        self.assertIn('forgotten', proof)
        self.assertIn('report', proof)


if __name__ == '__main__':
    unittest.main()
